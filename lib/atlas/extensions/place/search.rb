module Atlas
  module Extensions
    module Place
      module Search
        
        def self.included(included_in)
          included_in.class_eval do
            attr_accessor :score
            
            is_searchable
            set_solr_index 'places'

            # Replace the default functionality so that we do this through messaging or on a separate thread.
            alias :generate_solr_index :reindex

            extend Atlas::Extensions::Place::Search::ClassMethods
            include Atlas::Extensions::Place::Search::InstanceMethods

            after_save :reindex
          end
        end

        module ClassMethods

          # Convert our standard bounding box to a center lat/long with a radius in kilometers.  
          #
          # Also handles the {:center => {...}, :radius => ...} scenario as well.  If you don't provide a radius,
          # defaults to 10 km.
          #
          # Returns a hash of :center, :radius (which, technically, you could pass back in for no reason whatsoever):
          #
          #   { :center => { :latitude => 34.323488, :longitude => -102.892341 }, :radius => 15 }
          #
          def bounds_to_center_radius(bounds)
            center = nil
            radius = nil
            
            if bounds.present?
              if bounds.has_key? :sw
                # Now, let's look for places, using our bounding box and Spatial Solr.
                envelope = Envelope.from_coordinates([
                    [bounds[:sw][:longitude].to_f,bounds[:sw][:latitude].to_f],
                    [bounds[:ne][:longitude].to_f,bounds[:ne][:latitude].to_f]
                  ])
                center = envelope.center
                # radius = (center.spherical_distance(Point.from_x_y(bounds[:ne][:longitude].to_f, bounds[:ne][:latitude].to_f)) / 1000.0).abs
                radius = (center.spherical_distance(Point.from_x_y(center.x, envelope.upper_corner.y))) / 1000.0
              elsif bounds.has_key? :center
                center = Point.from_x_y(bounds[:center][:longitude].to_f, bounds[:center][:latitude].to_f)
                if bounds.has_key? :radius
                  radius = bounds[:radius]
                else
                  radius = 10
                end
              end
            end
            
            center.present? && { :center => { :latitude => center.lat, :longitude => center.lng }, :radius => radius } || {}
          end
          
          # Generate the Spatial Solr query based on our standard bounding box hash, or a 
          # :center => :latitude, :longitude and :radius.
          def spatial_query(bounds)
            sb = bounds_to_center_radius(bounds)
            if sb.present?
              "{!spatial lat=#{sb[:center][:latitude]} long=#{sb[:center][:longitude]} radius=#{sb[:radius]} unit=km calc=arc threadCount=2}"
            else
              ""
            end
          end
          alias :bounds_query :spatial_query
          
          # Query the Solr server.  Override to use PlaceResults instead of Solr::Results.
          def search_for(keywords, options = {})
            bounds = options[:specific] || options[:bounds]
            keywords = '*:*' if keywords.blank?
            logger.debug "Search Query: #{spatial_query(bounds)}#{keywords}"
            solr_server.find("#{spatial_query(bounds)}#{keywords}", options.merge(:results => Atlas::Extensions::Place::PlaceResults))
          end

          # Will use a simple spatial dismax search to find places within the given bounding box.  Pass
          # in a :bounds option with our standard [:sw][:latitude], [:sw][:longitude], etc. hash.
          #
          # Returns the same format as full_search.
          def search_within(keywords, options = {})
            bounds = options[:bounds] || nil
            keywords = '*:*' if keywords.blank?
          
            logger.debug "Search Query: #{spatial_query(bounds)}#{keywords}"
          
            if bounds.present?
              results = solr_server.find("#{spatial_query(bounds)}#{keywords}", options.merge(:qt => 'full', 
                  :results => Atlas::Extensions::Place::PlaceResults))
            else
              results = solr_server.find(keywords, options.merge(:qt => 'full', :results => Atlas::Extensions::Place::PlaceResults))
            end
          
            { :places => results, :selected => nil, :where => nil, :query => (keywords == '*:*' && '' || keywords) }
          end
          
          # Search for part of a term, such as "disn".  Useful for user's typing in searches while you try 
          # to autocomplete them.
          def partial_search(query, options = {})
            bounds = options[:bounds] || nil
            if bounds.present?
              results = solr_server.find("#{spatial_query(bounds)}name:#{query}*", options.merge(:qt => 'standard', 
                  :results => Atlas::Extensions::Place::PlaceResults))
            else
              results = solr_server.find("name:#{query}*", options.merge(:qt => 'standard', 
                  :results => Atlas::Extensions::Place::PlaceResults))
            end
            results
          end
          
          # Query for places.  Performs a where search first, unless otherwise indicated by the alternate
          # or specific options.
          #
          # Possible options:
          #
          # :bounds -       weight places higher within this box; standard :sw => :latitude, :longitude format
          # :latitude -     with :longitude, indicate the user's current location, to weight places nearby
          # :longitude -    see :latitude
          # :alternate -    the "where" guess (first result) of the original query was incorrect; select another 
          #                 (Atlas::Geography ID) 
          # :specific -     specify these specific bounds to search within; don't do a where search (i.e. drag 
          #                 the map); same format as :bounds
          #
          def full_search(keywords, options = {})
            latitude = nil
            longitude = nil
            bounds = options[:bounds]
            where = nil
            
            if options[:alternate].blank? && options[:specific].blank? && options[:skip_where].blank?
              where_results = Atlas::Geography.where_am_i(keywords, options.dup)
              
              keywords = where_results[:query]
              where = where_results[:where].models
              
              unless where.blank?
                selected = where.first
                bounds = selected.bounds
              end
              
              options.delete :fq
              
            # The user has indicated that our "where" guess was incorrect, and selected another.
            elsif options[:alternate].present?
              selected = Atlas::Geography.find(options[:alternate])
              bounds = selected.bounds 
              
              # Record when a user selects an alternate where result, i.e. we got it wrong!
              # Atlas::GeographicQueryLog.create :status => 'alternate', :query => query, :session_id => options[:session_id]

            # The user has sent in a specific bounding box in which to search.  Presumably the user is looking
            # at a map, dragging it around, and re-performing searches.
            elsif options[:specific].present?
              bounds = options[:specific]
            end

            keywords = '*' if keywords.blank?
            
            if bounds.present?
              results = solr_server.find("#{spatial_query(bounds)}#{keywords}", 
                  options.merge(:qt => 'geographic', :results => Atlas::Extensions::Place::PlaceResults))
              
              if results.documents.empty? && where.present?
                where[1..-1].each do |geography|
                  selected = geography
                  envelope = geography.read_attribute(:bounds).envelope
                  center = envelope.center
                  top_center = center.y + (center.y - envelope.lower_corner.y)
                  radius = center.spherical_distance(Point.from_x_y(center.x, top_center)) / 1000.0

                  results = solr_server.find("{!spatial lat=#{center.lat} long=#{center.lng} radius=#{radius} unit=km calc=arc threadCount=2}#{keywords}", 
                      options.merge(:qt => 'geographic', :results => Atlas::Extensions::Place::PlaceResults))
                    
                  break unless results.documents.empty?
                end
              end
            else
              results = solr_server.find(keywords, options.merge(:qt => 'full', :results => Atlas::Extensions::Place::PlaceResults))
            end
            
            { :places => results, :selected => selected, :where => where, :query => (keywords == '*' && '' || keywords) }
          end

          # Look up places by one or more place IDs in the search index.
          def find_from_search(*ids)
            unless ids.blank?
              results = {}
              ids.flatten.dice(20).each do |set|
                query = (set.map { |id| "(id:\"#{id}\")" }).join(' || ')
                search_results = search_for(query, :qt => 'standard', :rows => set.length)
                search_results.models.each do |result|
                  results[result.id] = result
                end
              end
              ids.flatten.map { |id| results[id] }.compact
            else
              []
            end
          end

          # Take a search document from Solr and convert it to a place.
          def from_search_document(document)
            place = Atlas::ReadOnly::Place.new
            place.readonly!

            place.id = document.delete('id')

            place.category = Atlas::Category.new :name => document.delete('category_name'), :slug => document.delete('category_slug')
            place.category.id = document.delete('category_id')
            place.category.readonly!
            
            place.slug = document.delete('slug') || ''
            place.latitude = document.delete('latitude')
            place.longitude = document.delete('longitude')
            place.created_at = Time.parse(document.delete('created_at')) if document['created_at']
            place.updated_at = Time.parse(document.delete('updated_at')) if document['updated_at']
            
            place.route = document.delete('route') if document['route']
            place.region = document.delete('region') if document['region']
            
            place.score = document['score']
            
            if document['contributor_id']
              document.delete('contributor_id').zip(document.delete('contributor')).each do |contrib_params|
                contributor = Atlas::Source.new(:name => contrib_params[1])
                contrib_params[0] =~ /([\w\-]+)([\!\+])(\*)?/
                contributor.id = $1
                
                # TODO!!!
                # contributor.publicly_visible = ($2 == "+")
                # contributor.creator = ($3 == '*')
                
                contributor.readonly!
                place.contributors << contributor
              end
            end
            
            place.tags = document.delete('keyword').map do |keyword| 
              t = Atlas::Tag.new(:name => keyword) 
              t.readonly!
              t
            end rescue Atlas::Util::ArrayAssociation.new(self, Atlas::Tag)

            place.moods = document.delete('mood').map do |mood| 
              m = Atlas::Mood.new(:name => mood) 
              m.readonly!
              m
            end rescue Atlas::Util::ArrayAssociation.new(self, Atlas::Mood)
            
            place.features = document.delete('feature').map do |feature| 
              f = Atlas::Feature.new(:name => feature) 
              f.readonly!
              f
            end rescue Atlas::Util::ArrayAssociation.new(self, Atlas::Feature)

            place.average_rating = document.delete('average_rating')
            place.number_of_ratings = document.delete('number_of_ratings').to_i || 0
          
            # TODO!!!
            # place.photo = ...
            
            place_attributes = Atlas::Util::ArrayAssociation.new(self, Atlas::ReadOnly::PlaceAttribute, :place_id)
            document.each do |key, value|
              if key =~ /\Aattr_(?:text|date|int|float)_(.*?)\Z/
               name = $1
               pa = Atlas::ReadOnly::PlaceAttribute.new :place => place, :attribute_definition => name
               pa.values = value.map { |v| Atlas::PlaceValue.new :value => v }
               place_attributes << pa
              end
            end
            place.place_attributes = place_attributes
            
            place
          end
          
          def many_to_solr_xml(places)
            outgoing = StringIO.new('', 'w')
            outgoing.printf('<add>')
            places.each { |p| p.search_document_xml(outgoing) }
            outgoing.printf('</add>')
            outgoing.string
          end
          
        end

        module InstanceMethods
          # The document to send to Solr, as a hash.
          def search_document
            document = {
              :id => self.id,
              :name => self.name.to_s,
              :slug => self.slug,
              :average_rating => self.average_rating,
              :number_of_ratings => self.number_of_ratings,
              :latitude => self.latitude,
              :longitude => self.longitude,
              :category_id => self.category.id,
              :category_name => self.category.name,
              :category_slug => self.category.slug,
              :belongs_to => self.category.hierarchy.map(&:id),
              :keyword => self.tags.map(&:to_s),
              :feature => self.features.map(&:to_s),
              :mood => self.moods.map(&:to_s),
              :created_at => self.created_at.utc.xmlschema,
              :updated_at => (self.updated_at || self.created_at).utc.xmlschema
            }

            if photos.present?
              photo = photos.first
              document.merge!({
                :photo_id => photo.id,
                :photo_url => photo.filename,
                :photo_square => photo.s3_key_for_modification(:square),
                :photo_square_doubled => photo.s3_key_for_modification(:square_doubled),
                :photo_large => photo.s3_key_for_modification(:large),
                :photo_map => photo.s3_key_for_modification(:map),
                :photo_details => photo.s3_key_for_modification(:details)
              })
            end
            
            document[:contributor_id] = self.contributors.map do |contributor|
              "#{contributor.id}#{contributor.visible_for?(self) && '+' || '!'}#{'*' if contributor.id == creator.id}"
            end
            document[:contributor] = self.contributors.map(&:to_s)
            document[:creator_id] = "#{creator.id}#{creator.visible_for?(self) && '+' || '!'}*"
            document[:creator] = creator.name

            if routes.exists?
              document.merge! routes.first.to_hash.symbolize_keys
            end

            if regions.exists?
              document.merge! regions.first.to_hash.symbolize_keys
            end

            self.details.each do |attribute|
              document["attr_text_#{attribute.attribute_definition}".to_sym] = attribute.values.map(&:to_s)
            end

            document
          end

          class Boost
            def initialize(place)
              @place = place
              @boost = 1.0
            end
            
            def <<(value)
              if value.kind_of? Array
                @boost += value.first
                RAILS_DEFAULT_LOGGER.debug "#{@place.name} (#{@place.id}): #{value.last} - #{value.first}"
              else
                @boost += value
              end
              @boost
            end
            
            def value
              @boost
            end
          end
          
          # Adjust the boost of the place in the search index, e.g. for ratings...
          def boost
            boost = Boost.new self
            boost << [1.0, "description"] if self.details.include?(:description)
            boost << [5.0, "long description"] if self.details.include?(:description) && self.details.description.to_s.split(/\b/).length > 10
            boost << [1.0, "rich content"] if self.place_attributes.length > 3
            boost << [3.0, "very rich content"] if self.place_attributes.length > 6
            boost << [5.0, "photos"] if self.photos.length > 0
            boost << [2.0, "moods"] if self.moods.length > 0
            boost << [2.0, "features"] if self.features.length > 0
            boost << [2.0, "contributors"] if self.contributors.length > 1
            boost << [3.0, "active contributors"] if self.contributors.length > 3
            
            times_saved = Atlas::SavedPlace.count(:conditions => ["place_id = ?", self.id])
            boost << [4.0, "saved"] if times_saved > 0
            boost << [8.0, "popular"] if times_saved > 2
            
            boost << [self.average_rating, "average rating"] if self.number_of_ratings > 2
            boost.value
          end

          # Reindex the place through the message server.  Could be a delay; don't use with the
          # data loader!
          def reindex(autocommit = true)
            if defined?(RABBIT_MQ) && defined?(Bunny) && RABBIT_MQ
              publish_to_rabbit
            else
              reindex!
            end
          end
          alias :update_search_index :reindex

          # Publish this place's ID to the RabbitMQ server.
          #
          # TODO:  Make the queue, exchange, and key configurable!
          def publish_to_rabbit
            logger.debug "Publishing #{self.name} (#{self.id}) to Rabbit..."
            b = Bunny.new RABBIT_MQ
            b.start
            reindex = b.queue 'reindex', :durable => true
            exchange = b.exchange 'publicearth', :type => :direct, :durable => true
            reindex.bind exchange, :key => 'indexer'
            # reindex.publish "#{self.id} #{self.updated_at.to_i * 1000}", :persistent => true
            reindex.publish "#{self.id} abc", :persistent => true
          end
          
          # This reindexes a place on the current thread, while reindex using a separate thread.  Use of
          # reindex or update_search_index is preferred; this method is used by the thread to perform
          # the actual reindexing.
          def reindex!
            logger.debug "Updating #{self.name} (#{self.id}) to Solr directly..."
            indexed if generate_solr_index
          end
          alias :reindex_with_solr :reindex!

          # Indicate that this place has been added to the search index or reindexed.
          def indexed
            Time.parse(PublicEarth::Db::Place.connection.select_value("select place.indexed('#{self.id}')"))
          end

        end
      end
    end
  end
end

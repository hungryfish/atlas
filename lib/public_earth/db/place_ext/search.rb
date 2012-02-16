module PublicEarth
  module Db
    module PlaceExt
      module Search

        def self.included(included_in)
          included_in.class_eval do
            is_searchable
            set_solr_index 'places'
            
            # Replace the default functionality so that we do this through messaging or on a separate thread.
            alias :generate_solr_index :reindex
            
            extend PublicEarth::Db::PlaceExt::Search::ClassMethods
            include PublicEarth::Db::PlaceExt::Search::InstanceMethods
          end
        end

        module ClassMethods

          # Take the parameters for a bounding box from the HTTP request and turn them into a search
          # engine query.
          def bounds_query(bounds)
            if bounds.present?
              longitudes = [bounds[:sw][:longitude], bounds[:ne][:longitude]]
              latitudes = [bounds[:sw][:latitude], bounds[:ne][:latitude]]
              "search_longitude:[#{longitudes.min} TO #{longitudes.max}] && " + "search_latitude:[#{latitudes.min} TO #{latitudes.max}]"
            else
              nil
            end
          end

          # Look for places using a single set of search keywords.  Tries to interpret not only the search
          # terms, but the region in which you're looking for places...with varying degrees of success.
          #
          # TODO:  Needs work.  Move to Google geocoder/enhanced Solr queries.
          def search_with_geography(keywords, options = {})
            unless keywords.blank?
              # For backwards compatibility
              options[:count] ||= options[:rows] || 10
              
              parameters = {
                  :start => options[:start] && options[:start].to_i || 0,
                  :rows => options[:count] && options[:count].to_i > 0 && options[:count].to_i < 100 && options[:count].to_i || 10
                }
              
              parameters[:fq] = bounds_query(options[:bounds]) if options[:bounds].present?
              
              places = []
              facets = []
              
              results = PublicEarth::Db::Place.search_for keywords, parameters
              places = results.models
              
              # Tack on a possible map location, such as a city or country?  Maybe the user was searching
              # to move the map, not look for places?
              where = nil
              unless options[:e]
                where = PublicEarth::Db::Where.am_i?(keywords, options[:bounds])
                where = nil if where.score.nil?
              end
              
              # A bold substitute for a rules engine!  (There is a paper flowchart of this somewhere...)
              if options[:bounds]
                if places.blank?
                  if where.present? 
                    [:reposition, where, nil, nil]
                  else
                    [:display, nil, nil, nil]
                  end
                else
                  if where.present?
                    if where.score > 3.0
                      [:prompt, where, results]
                    else
                      [:display, where, results]
                    end
                  else
                    [:display, nil, results]
                  end
                end
              else
                if places.blank? && where.blank?
                  [:display, nil, nil]
                else
                  if where.present?
                    if where.score > 0.4 && !options[:recursed]
                      if where.score > 2.0
                        k = keywords.downcase
                        # Temporary stop terms...FIX!!!
                        ("in for from near by where around over under " + where.name.downcase).split(/\s+/).each do |word|
                          k.gsub! /\b#{word}\b/, ''
                        end
                        options.merge!({ :bounds => where.bounds, :recursed => true })
                        
                        again = search_with_geography(k, options)
                        if again[2].blank?
                          [:reposition, where, nil, nil]
                        else
                          [:display, where, again.last]
                        end
                      else
                        [:prompt, where, results]
                      end
                    else
                      [:suggest, where, results]
                    end
                  else
                    [:display, nil, results]
                  end
                end
              end
            else
              [:display, nil, nil, nil]
            end
          end
          
          # Query the Solr server.  Override to use PlaceResults instead of Solr::Results.
          def search_for(keywords, options = {})
            solr_server.find(keywords, options.merge(:results => PublicEarth::Search::PlaceResults))
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
              ids.flatten.map { |id| results[id] }
            else
              []
            end
          end
          
          # Take a search document from Solr and convert it to a place.
          def from_search_document(document)
            place = PublicEarth::Db::Place.new

            place.id = document.delete('id')
            place.slug = document.delete('slug') || ''
            place.category = PublicEarth::Db::Category.new :id => document.delete('category_id'), 
                :name => document.delete('category').first, :slug => document.delete('category_slug')
            place.tags = document.delete('keyword').map{ |tag| PublicEarth::Db::Tag.create(tag)} rescue []
            place.name = document['attribute_text_name'] || document['name']
            place.rating = document['rating']
            place.number_of_ratings = document['number_of_ratings'].to_i || 0

            # Search ranking
            place.score = document['score'] 

            # TODO:  Feature comments?!?
            results = []
            
            document.each do |key, value|
              if key =~ /\Aattr_(?:text|date|int|float)_(.*?)\Z/
                name = $1

                # We skip the comments in here, because we don't want them as attributes on the place.
                unless name =~ /_comments\Z/
                  # Grab the comment, if there is one...
                  comment = document["#{key}_comments"]
                
                  if value.kind_of? Array
                    value.each do |array_value|
                      results << {
                        'attribute_language' => 'en',
                        'attribute_definition_name' => name,
                        'attribute_value' => array_value
                        # 'attribute_comments' => comment
                      }
                    end
                  else
                    results << {
                      'attribute_language' => 'en',
                      'attribute_definition_name' => name,
                      'attribute_value' => value
                      # 'attribute_comments' => comment
                    }
                  end
                end
                
              else
                place.write_attribute(key, value)
              end
            end
            
            place.details = PublicEarth::Db::Details.new(place, nil, nil, results)
            place
          end

        end

        module InstanceMethods
          # The document to send to Solr, as a hash.
          def search_document
            document = {
              :id => self.id,
              :name => self.name.to_s,
              :slug => self[:slug],
              :rating => self.rating[:average_rating],
              :number_of_ratings => self.rating[:rating_count].to_i,
              :latitude => @attributes[:latitude],
              :longitude => @attributes[:longitude],
              :category_id => self.category_id,
            }

            document[:route] = @attributes[:route] if @attributes[:route]
            document[:route_length] = @attributes[:route_length] if @attributes[:route_length]
            document[:encoded_route] = @attributes[:encoded_route] if @attributes[:encoded_route]
            document[:encoded_route_levels] = @attributes[:encoded_route_levels] if @attributes[:encoded_route_levels]
            document[:encoded_route_zoom_factor] = @attributes[:encoded_route_zoom_factor] if @attributes[:encoded_route_zoom_factor]
            document[:encoded_route_num_zoom_levels] = @attributes[:encoded_route_num_zoom_levels] if @attributes[:encoded_route_num_zoom_levels]
            document[:region] = @attributes[:region] if @attributes[:region]
            document[:region_area] = @attributes[:region_area] if @attributes[:region_area]
            document[:encoded_region] = @attributes[:encoded_region] if @attributes[:encoded_region]
            document[:encoded_region_levels] = @attributes[:encoded_region_levels] if @attributes[:encoded_region_levels]
            document[:encoded_region_zoom_factor] = @attributes[:encoded_region_zoom_factor] if @attributes[:encoded_region_zoom_factor]
            document[:encoded_region_num_zoom_levels] = @attributes[:encoded_region_num_zoom_levels] if @attributes[:encoded_region_num_zoom_levels]
            document[:keyword] = self.tags.map { |tag| tag['name'] }
            document[:category] = self.category && [self.category.name] || 'Not Yet Categorized'
            document[:category_slug] = self.category && self.category.slug
            document[:belongs_to] = self.category.belongs_to.map(&:id)
            document[:featured] = self.featured if @attributes[:featured]
            document[:head] = self.head
            
            # document[:flyout_photo] = (self.photos.map { |photo| photo.modification(:map) && photo.modification(:map).url || nil}).compact
            
            # Temporary...we need a better way...
            sources = PublicEarth::Db::Source.contributed_to(self.id, true)
            document[:source] = sources.map(&:name)
            document[:source_id] = sources.map(&:id)
            
            # Since the collection field is for sorting and display only--not for search--we tack the ID
            # of the collection onto the end.  We'll strip it off again before displaying, and it being
            # there on the end shouldn't affect sorting.  But we need both the ID and the name, since the
            # name of a collection is not unique.
            # document[:collection] = self.collections.map { |collection| "#{collection.name} #{collection.id}"}
            # document[:search_collection] = self.collections.map { |collection| collection.name }

            # TODO:  We need to save the correct types!
            self.details.each do |attribute|
              begin
                if attribute.allow_many?
                  collection = []
                  comments = []
                  attribute.each do |individual|
                    unless individual.value.blank?
                      collection << individual.value
                      comments << individual.comments || '' 
                    end
                  end
                  document["attr_text_#{attribute.name}".to_sym] = collection
                  document["attr_text_#{attribute.name}_comments".to_sym] = comments
                else
                  unless attribute.value.blank?
                    document["attr_text_#{attribute.name}".to_sym] = attribute.value
                    document["attr_text_#{attribute.name}_comments".to_sym] = attribute.comments unless attribute.comments.blank?
                  end
                end
              rescue
              end
            end
  
            document
          end

          # Adjust the boost of the place in the search index, e.g. for ratings...
          def boost
            1.0
          end

          # Reindex the place through the message server.  Could be a delay; don't use with the
          # data loader!
          def reindex(autocommit = true)
            message = {:id => self.id, :document => self.search_document, :boost => self.boost}.to_json
            if defined?(RABBIT_MQ) && defined?(Bunny)
              Bunny.run RABBIT_MQ do |rabbit|
                queue = rabbit.queue "sisyphus__reindex_place_document"
                queue.publish(message)
              end
            else
              Sisyphus.async_reindex_place_document(message)
            end
          end
          alias :update_search_index :reindex

          # This reindexes a place on the current thread, while reindex using a separate thread.  Use of
          # reindex or update_search_index is preferred; this method is used by the thread to perform
          # the actual reindexing.
          def reindex!
            indexed if generate_solr_index
          end
          alias :reindex_with_solr :reindex!

          # Indicate that this place has been added to the search index or reindexed.
          def indexed
            Time.parse(PublicEarth::Db::Place.connection.select_value("select place.indexed('#{self.id}')"))
          end

          # Find similar places in the search indexes based on category and keyword.
          #
          # TODO:  Currently not properly implemented with the latest search indexes.
          def more_like_me
            # super(:similarities => 'category,keyword')
            raise "The more_like_me functionality is not implemented."
          end
        end
      end
    end
  end
end

module Atlas
  class Geography < ActiveRecord::Base

    include Atlas::Extensions::Geography::Formats

    is_searchable 
    set_solr_index :where
    attr_accessor :score, :highlights, :accuracy, :content_format, :distance
  
    STOP_WORDS = %w(a an and are around as at be but by close for if in into is it near nearby no not of on or over such that the their then there these they this to under was will with)

    has_many :points, :class_name => "Atlas::GeographicPoint"
    has_many :regions, :class_name => "Atlas::GeographicRegion"
    has_many :synonyms, :class_name => "Atlas::GeographicSynonym"
  
    has_many :as_subject, :class_name => "Atlas::GeographicRelationship", :foreign_key => "subject"
    has_many :parents, :through => :as_subject, :source => :predicate, :conditions => ["geographic_relationships.relation = 'part-of'"]
  
    has_many :as_predicate, :class_name => "Atlas::GeographicRelationship", :foreign_key => "predicate"
    has_many :children, :through => :as_predicate, :conditions => { :relation => "part_of" }, :source => :predicate
  
    named_scope :containing, lambda { |latitude, longitude|
        { 
          :select => "geographies.*, st_distance_sphere(st_setsrid(st_makepoint(#{longitude}, #{latitude}), 4326), point) as distance",
          :joins => 'left join geographic_points gp on gp.geography_id = geographies.id',
          :conditions => "st_setsrid(st_makepoint(#{longitude}, #{latitude}), 4326) && bounds",
          :order => 'distance ASC'
        }
      }
    
    named_scope :cities, :conditions => "what = 'City'"
    named_scope :countries, :conditions => "what = 'Country'"
    
    def self.check_bounding_box(bounds)
      if bounds[:sw][:latitude] == bounds[:ne][:latitude] && bounds[:sw][:longitude] = bounds[:ne][:longitude]
        bounds[:sw][:latitude] -= 0.001
      end
    end
    
    # Find the nearest place to where you are.  Prefers a city, but will default to a U.S. State, British county, 
    # Canadian Province, and fall back to a country.  
    #
    # TODO:  Add Mexican provinces, French provinces, Russian states and German states.
    def self.around(*bounds)
      envelope = nil
      c = nil
      if bounds.first.kind_of? Hash
        bounds = bounds.first
        envelope = Envelope.from_coordinates([
            [bounds[:sw][:longitude].to_f,bounds[:sw][:latitude].to_f],
            [bounds[:ne][:longitude].to_f,bounds[:ne][:latitude].to_f]
          ])
        c = envelope.center
        
      elsif bounds.length == 2
        envelope = Envelope.from_points([
          Point.from_x_y(bounds.last.to_f - 0.25, bounds.first.to_f - 0.25),
          Point.from_x_y(bounds.last.to_f + 0.25, bounds.first.to_f + 0.25)])
        bounds = {}
        bounds[:sw] = { :latitude => envelope.lower_corner.y, :longitude => envelope.lower_corner.x }
        bounds[:ne] = { :latitude => envelope.upper_corner.y, :longitude => envelope.upper_corner.x }
        c = envelope.center
        # c = Point.from_x_y(bounds.last, bounds.first)
      end
      
      check_bounding_box(bounds)

      places = []
      
      # Width of the bounds in degrees
      width = (envelope.lower_corner.y - envelope.upper_corner.y).abs
      
      # If you're in far enough, try neighborhoods first...
      if width < 0.045
        places << find_by_sql("
          select geographies.*, st_distance_sphere(st_setsrid(st_centroid(st_makebox2d(
            st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
            st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326), st_centroid(bounds)) as distance
            from geographies
            left join geographic_regions gr on geographies.id = gr.geography_id
            where what = 'Neighborhood' and 
                bounds && 
                st_setsrid(st_envelope(st_makebox2d(
                  st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
                  st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326) and
                st_within(st_setsrid(st_makepoint(#{c.x}, #{c.y}), 4326), gr.region) 
            order by distance")
      end
      
      if places.flatten.empty? && width < 5.0
        places << find_by_sql("
          select geographies.*, st_distance_sphere(st_setsrid(st_centroid(st_makebox2d(
            st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
            st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326), st_centroid(bounds)) as distance
            from geographies
            where what = 'City' and bounds && 
              st_setsrid(st_envelope(st_makebox2d(
                st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
                st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326) and
              st_within(st_setsrid(st_makepoint(#{c.x}, #{c.y}), 4326), bounds)
            order by distance")
      end
      
      if places.flatten.empty?    
        places << find_by_sql("
          select geographies.*, st_distance_sphere(st_setsrid(st_centroid(st_makebox2d(
            st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
            st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326), st_centroid(bounds)) as distance
            from geographies
            left join geographic_regions gr on geographies.id = gr.geography_id
            where what in ('County, GB', 'Province', 'State') and 
                bounds && 
                st_setsrid(st_envelope(st_makebox2d(
                  st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
                  st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326) and
                st_within(st_setsrid(st_makepoint(#{c.x}, #{c.y}), 4326), gr.region) 
            order by distance")
      end
      
      if places.flatten.empty?
        places << find_by_sql("
          select geographies.*, st_distance_sphere(st_setsrid(st_centroid(st_makebox2d(
            st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
            st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326), st_centroid(bounds)) as distance
            from geographies
            where what not in ('City', 'County, GB', 'Province', 'State') and 
                bounds && 
                st_setsrid(st_envelope(st_makebox2d(
                  st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}),
                  st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]}))), 4326) and
                st_within(st_setsrid(st_makepoint(#{c.x}, #{c.y}), 4326), bounds) 
          order by distance asc")
      end
      
      places.flatten
    end
    
    # Temporarily using Google Reverse Geocoder to obtain City Level (Accuracy=4) Geography models.
    # def self.locations_containing_point(lat, long)
    #   models = Atlas::Google.where_am_i("#{lat}, #{long}")[:where]
    #   
    #   # Find closest accuracy to 4, city level.
    #   [models.map {|m| {:distance => (4 - m.accuracy).abs, :model => m}}.sort_by {|m| m[:distance]}.first[:model]]
    # end
    
    # Query for a geographic location.  There are a couple of options that may be passed in:
    #
    # :bounds -       weight places higher within this box; standard :sw => :latitude, :longitude format
    # :latitude -     with :longitude, indicate the user's current location, to weight places nearby
    # :longitude -    see :latitude
    #
    # Returns a hash with the modified :query and the :where results found.  The query will be 
    # modified by pulling out the matching keywords from the first where result.
    #
    def self.where_am_i_according_to_publicearth(query, options = {})
      latitude = nil
      longitude = nil
    
      if options[:bounds].present?
        bounds = options.delete :bounds
        center = Atlas::Geography.center(bounds)
        latitude = center[:latitude]
        longitude = center[:longitude]
      elsif options[:latitude].present? && options[:longitude].present?
        latitude = options.delete :latitude
        longitude = options.delete :longitude
      end
    
      # Boost nearby locations in our where search.  This allows Denver, IA to supercede Denver, CO when 
      # searching in Iowa.
      if latitude.present? && longitude.present?
        options[:bf] = "distance(geography,#{latitude.to_f},#{longitude.to_f})^10.0"
      end

      # Refine our search?
      geographies = Atlas::Geography.search_for query, options.merge(:rows => 10, :highlight => 'name,keyword', :qt => 'standard')
      selected = nil
      if geographies.present?
        selected = geographies.models.first
        bounds = selected.bounds

        # Record the where search...where are people looking.
        # Save the session ID with the search, so we can track a individual through their query history.
        # Atlas::GeographicQueryLog.create :query => query, :found => "#{selected.label} (#{selected.id})", :session_id => options[:session_id]
      
        # Revise the query based on what was found in the geography!!!
        keywords = (selected.highlights.values.uniq.flatten.map {|m| m.scan /<em>([^<]+)<\/em>/}).flatten.uniq.map {|k| k.downcase}
        tokens = query.downcase.split(/[\s\,\.\;\!\?]+/)
        tokens.delete_if {|t| keywords.include?(t)}
    
        # Strip any dangling stop words off the front of the search query
        while tokens.length > 0 
          STOP_WORDS.include?(tokens.first) && tokens.shift || break
        end

        # Strip any dangling stop words off the end of the search query
        while tokens.length > 0 
          STOP_WORDS.include?(tokens.last) && tokens.pop || break
        end
    
        # Rebuild the query, simplified, without the search terms  
        query = tokens.join(" ")
      else
        # Record that the "where" search failed.
        # Atlas::GeographicQueryLog.create :status => 'failed', :query => query, :session_id => options[:session_id]
      end
      
      { :query => query, :where => geographies }
    end
  
    # TODO:  Temporarily using Google's geocoding API for the where_am_i query.  Note that this will ONLY
    # work with pure where queries, i.e. an address, name of a city, state, country, landmark, etc.  It
    # will not work for Place.full_search using mixed queries, such as "hotels in denver".  
    def self.where_am_i(query, options = {})
      Atlas::Google.where_am_i(query, options)
    end
    
    def self.center(bounding_box)
      { 
        :latitude => (bounding_box[:sw][:latitude].to_f + bounding_box[:ne][:latitude].to_f) / 2.0,
        :longitude => (bounding_box[:sw][:longitude].to_f + bounding_box[:ne][:longitude].to_f) / 2.0,
      }
    end
  
    # Query the Solr server.  Override to use PlaceResults instead of Solr::Results.
    def self.search_for(keywords, options = {})
      solr_server.find(keywords, options.merge(:results => Geography::Results))
    end
    
    def bounds(results = nil)
      envelope = read_attribute(:bounds).envelope
      {
        :sw => {
          :latitude => envelope.lower_corner.lat,
          :longitude => envelope.lower_corner.lng,
          :lat => envelope.lower_corner.lat,
          :lon => envelope.lower_corner.lng
        },
        :ne => {
          :latitude => envelope.upper_corner.lat,
          :longitude => envelope.upper_corner.lng,
          :lat => envelope.upper_corner.lat,
          :lon => envelope.upper_corner.lng
        }
      }
    end
  
    def latitude
      read_attribute(:bounds).envelope.center.y
    end
    
    def longitude
      read_attribute(:bounds).envelope.center.x
    end
    
    # Compute the distance from the center of the bounds and the center of this geography.  Returns the
    # value and saves it in the @distance property.
    #
    # If you pass in a :center => ..., :radius for bounds, that works too.
    def distance_from(bounds)
      center = Atlas::Place.bounds_to_center_radius(bounds)[:center]
      
      # We ask PostGIS to compute this in meters...
      self.distance = Atlas::Geography.connection.select_value("select st_distance_sphere(
          st_transform(st_setsrid(st_makepoint(#{longitude}, #{latitude}), 4326), 2163), 
          st_transform(st_setsrid(st_makepoint(#{center[:longitude]}, #{center[:latitude]}), 4326), 2163)
        ) as distance").to_f
    end
    
    def name
      self.label
    end
    alias :to_s :name
    
    def search_document
      doc = {
        :id => id,
        :name => label,
        :keyword => synonyms.map(&:label),
        :population => population | 0,
        :what => what,
        :bounds => read_attribute(:bounds).as_ewkt
      }
    
      # First level keywords -- from parent, if "part-of" something
      parents.each do |parent|
        doc[:keyword] << parent.label # "\"#{parent.label}\"|0.5"
        parent.synonyms.each do |synonym|
          doc[:keyword] << synonym.label # "\"#{synonym.label}\"|0.5"

          # Second level keywords -- from parent's parent, if parent is "part-of" something
          parent.parents.each do |grandparent|
            doc[:keyword] << grandparent.label # \"#{grandparent.label}\"|0.25"
            grandparent.synonyms.each do |grand_synonym|
              doc[:keyword] << grand_synonym.label # "\"#{grand_synonym.label}\"|0.25"
            end
          end
        end
      end
    
      doc[:geography] = Atlas::Geography.connection.select_values("
          select geometry from (
            select st_astext(region) as geometry from geographic_regions where geography_id = #{id} union 
            select st_astext(point) from geographic_points where geography_id = #{id}
          ) geometries")
      doc
    end
  
    def boost
      case what 
      when "City"
        if population > 500000
          10.0
        elsif population > 100000
          7.0
        elsif population > 20000
          4.0
        else
          2.0
        end
      when "Neighborhood"
        0.5
      when "State"
        1.5
      when "County, GB"
        10.0
      # when "Country"
      #   1.0
      else
        1.0
      end
    end
  
    class Results < PublicEarth::Search::Solr::Results
      def models
        @models ||= documents.map do |doc| 
          g = Atlas::Geography.new :label => doc['name'], :what => doc['what'], :population => doc['population'], :score => doc['score']
          g.id = doc['id']  # protected...
          g.bounds = Polygon.from_ewkt doc['bounds'] if doc['bounds']
          g.highlights = @highlights[g.id.to_s].symbolize_keys
          g
        end
      end
    end
  
  end
end
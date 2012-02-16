module PublicEarth
  module Db
    module CollectionExt
      module QueryManager
        
        WHAT_ZOOM_TO_KM = [0, 2.775, 4.44, 6.66, 8.325, 9.99, 11, 111, 277.5, 555, 1110]
        
        # Manages the entire descriptor:  query, where, center, and bounds.
        #
        # Note:  If you modify this query directly, rather than using the methods in PublicEarth::Db::Collection,
        # you must trigger collection.changed, or your changes will not be saved!
        #
        class What
          attr_reader :calculated_bounds, :sort, :total_found
          
          # If you include the json_string, will parse the JSON string (from the database) and populate
          # the What object with meaningful information we can work with programatically.
          def initialize(json_string = nil)
            if json_string.present?
              json = ActiveSupport::JSON.decode(json_string)

              # The easy bit...
              @where = json['where']
              self.limit = json['limit']
              @sort = json['sort']
              
              # Slightly harder...
              @center = center_from_json(json['center'])
              @bounds = bounds_from_json(json['bounds'])

              # We descend into parser hell!  Just kidding...it's not that bad...
              @query = Query.new(json['query'])
            else
              @query = Query.new
            end
          end

          # Return the query handler for the collection.
          def query
            @query
          end
  
          # Return the collection of PublicEarth::Db::Place objects directly attached to this query.
          def places
            Atlas::Place.find_from_search(*(query[:places] || []))
          end

          # Return the collection of PublicEarth::Db::Category objects directly attached to this query.
          #
          # TODO:  Optimize this query!
          def categories
            (query[:categories] || []).map { |id| PublicEarth::Db::Category.find_by_id(id) }
          end
          
          # Return the collection of PublicEarth::Db::Source objects directly attached to this query.
          #
          # TODO:  Optimize this query!
          def sources
            (query[:sources] || []).map { |id| PublicEarth::Db::Source.find_by_id(id) }
          end
  
          # These are in order of priority:  center, bounds, where
  
          # Return either a latitude/longitude or a place ID as the center of the collection.  If the 
          # places method was called with a custom center and this collection has no default center,
          # this method will return that custom center.
          def center
            @center || @override_center
          end
  
          # If you pass in a hash, it should contain the :latitude and :longitude keys for centering on
          # that point.  If you pass in a Place, will center on that place and by default include it in
          # the results.  To not include it, set place.visible = false on the place object.
          def center=(value)
            @center = value
          end

          # Possible formats:
          #
          #   'center': { 'latitude': -34.187, 'longitude': 104.3342 }
          #   'center': { 'id': '233q4-adfa32rf-23afadsf-95stgaf', 'include': true }
          #
          # The second format will pull a place for the center point.  If "include" is true, the place
          # will be included in the results.
          #
          # Pass in the value for the json 'center' field, e.g. bounds_from_json(json['center']).  Does not 
          # set the @center instance variable, but merely returns the value it might be set to, so you 
          # can use this method for test parsing information.
          #
          # Returns nil if the center could not be parsed.
          def center_from_json(json = {})
            center = nil
            if json
              json = { 'id' => json } if json.kind_of? String
              json.stringify_keys!
              if json['latitude'] && json['longitude']
                center = { :latitude => json['latitude'].to_f, :longitude => json['longitude'].to_f }
              elsif json['place'] || json['id']
                center = Atlas::Place.find_from_search(json['place'] || json['id'])
                center.center_of_collection = true if json['include'] == true || json['include'] == 'true'
              end
            end
            center
          end
          
          # Convert the center value to a hash for inclusion in the JSON.
          def center_to_json
            if center.kind_of? PublicEarth::Db::Place
              hash = { :place => center.id }
              hash[:include] = center[:center_of_collection] if center[:center_of_collection]
              hash
            elsif center.kind_of? Hash
              center
            end
          end
          
          # Return a bounding box as the search area for a collection.
          def bounds
            @bounds
          end
  
          # Should be similar to the standard bounds:  
          # 
          #   'bounds': { 'sw': { 'latitude': ..., 'longitude': ...}, 'ne': ... }
          #
          def bounds=(value)
            @bounds = value
          end
  
          # Should be similar to the standard bounds:  
          # 
          #   'bounds': { 'sw': { 'latitude': ..., 'longitude': ...}, 'ne': ... }
          #
          # Pass in the value for the json 'bounds' field, e.g. bounds_from_json(json['bounds']).  Does not 
          # set the @center instance variable, but merely returns the value it might be set to, so you 
          # can use this method for test parsing information.
          #
          # Returns nil if the center could not be parsed.
          def bounds_from_json(json = nil)
            bounds = nil
            if json.kind_of?(Hash) && json['sw'].kind_of?(Hash) && json['ne'].kind_of?(Hash)
              bounds = {}
              bounds[:sw][:latitude] = json['sw']['latitude']
              bounds[:sw][:longitude] = json['sw']['longitude']
              bounds[:ne][:latitude] = json['ne']['latitude']
              bounds[:ne][:longitude] = json['ne']['longitude']
            end
            bounds
          end
          
          # Return a traditional "where" query to run for the centroid of the collection.
          def where
            @where 
          end
  
          def where=(value)
            @where = value
          end
  
          def limit
            @rows || 10
          end
          
          def limit=(value)
            @rows = value && value.to_i > 0 && value.to_i || 10
          end
          
          def to_hash 
            hash = {}
            hash[:query] = @query unless @query.blank?
            hash[:center] = center_to_json unless @center.blank?
            hash[:bounds] = @bounds unless @bounds.blank?
            hash[:where] = @where unless @where.blank?
            hash
          end
  
          def to_json(*a)
            to_hash.to_json(*a)
          end
  
          # Checks to make sure there's a query to search on.  If the query is invalid or can't be parsed for
          # Solr, this will return false.
          def searchable?
            @query.to_query =~ /\w/
          end
          
          # Query for places associated with this collection.  You can pass in the following options:
          #
          # start::     results starting index, for paging
          # sort::      sort by this field
          # rows::      the maximum number of results to return
          # bounds::    the bounds hash to search within (bounds[:sw][:latitude], etc.)
          # where::     a custom "where" query; overrides the one associated with the collection, if present 
          #
          # Returns the places found matching the current collection query, coupled with the supplied 
          # options.  Does not store or set the results anywhere in the object, so you'll need to cache
          # the results locally.
          #
          # Return an empty array if the query is invalid or no places were found.
          def search_for_places(options = {})
            @override_center = nil
            query = to_solr(options[:where])
            query.delete(:fq) if query[:fq].nil?
            query.merge!(:specific => options[:bounds]) unless options[:bounds].blank?
            unless query.blank?
              results = Atlas::Place.search_for query.delete(:q),
                  query.merge(
                      :start => options[:start] && options[:start].to_i || 0,
                      :rows => options[:rows] && options[:rows].to_i > 0 && options[:rows].to_i <= 100 && options[:rows].to_i || limit,
                      :sort => options[:sort] || @sort,
                      :fl => options[:fields]
                    )

              place_ids = results.documents.map {|d| d['id']}
              models = results.models
              
              @total_found = results.found
              
              static_places = places
              static_places.each do |place|
                models << place unless place_ids.include? place.id
              end
              
              # Pull in any places manually...
              # places.each do |place|
              #   models << place unless place_ids.include? place.id
              # end
              models
            else
              models = []
            end
            models
          end
          
          # Returns a hash with the :q key set to the query string, and the :fq set to the where filter, for
          # Solr.  If there is no "where" value, :fq will be nil.
          #
          # If the query doesn't have a location defined, pass in where manually.  If that's a
          # string, does a search for that place via the geocoder ("Denver, CO").  If it's a hash that looks
          # like center, e.g. {:latitude => ..., :longitude => ...}, { :id => ... }, does a center-point lookup.
          # If it looks like a bounds, e.g. {:sw => {:latitude ...} ...}, does a bounds lookup.
          #
          # The where in the query takes precedence over the where passed in.  If you'd like to force your
          # custom where query through, simply unset the where clauses using reset_where.  Careful not to save
          # it though, or the where will be blown away!
          #
          # Also sets the :qt value to "standard", so that if you'd like to pass the result raw into Solr, you
          # may.  Before doing that, you should call searchable? to check that a valid hash will be returned.
          def to_solr(where = nil)
            query = @query.to_query
            if query.present? || @sort.present?
              {:q => "#{filter_query || filter_override(where)}#{query.present? && query || '*:*'}", :qt => 'standard', :rows => limit, :sort => @sort} 
            end
          end

          # Generate a filter query based on a value.  
          #
          #   * Pass in a string:  does a search for that place via the geocoder
          #   * Pass in a place:  creates a rough bounding box around that place
          #   * Pass in a hash with an :id:  look up the place and center a bounding box around the place
          #   * Pass in a hash with :latitude and :longitude:  create a bounding box around the point and return
          #   * Pass in a hash with :sw and :ne:  Convert the hash to a bounding box
          #
          def filter_override(where)
            unless where.blank?
              if where.kind_of? String
                geocode_where(where)
              elsif where.kind_of? Atlas::Place
                center_to_search_filter({ :latitude => center.latitude, :longitude => center.longitude })
              elsif where.kind_of? Hash
                where.symbolize_keys!
                radius = where[:radius] && where.delete(:radius).to_f || nil
                
                if where.has_key?(:place) || where.has_key?(:center)
                  @override_center = Atlas::Place.find_from_search(where[:center] || where[:place]).first
                  if @override_center
                    @override_center.center_of_collection = true unless @override_center.nil?
                    center_to_search_filter({ :latitude => @override_center.latitude, :longitude => @override_center.longitude, :radius => radius }) 
                  end
                elsif where.has_key?(:latitude) && where.has_key?(:longitude)
                  center_to_search_filter(where.merge(:radius => radius))
                elsif where.has_key?(:sw) && where.has_key?(:ne)
                  bounds_to_search_filter(where)
                elsif where.has_key?(:search)
                  geocode_where(where)
                end
              end
            end
          end
          
          # Generate the query filter associated with the location of this collection.  Checks in the following
          # order:
          #
          #   # The center of the collection
          #   # The bounds of the collection
          #   # The where query for the collection
          #
          def filter_query
            (center && center_query) || (bounds && bounds_query) || (where && geocode_where(where)) || nil
          end


          # Convert a "where" string into a latitude and longitude query, e.g. "London, UK", for the filter.
          def geocode_where(location)
            results = Atlas::Geography.where_am_i(location)
            if results
             # bounds_to_search_filter(results.bounds)
              bounds_to_search_filter(results[:where].first.bounds)
            end
          end




          # Convert the center to a latitude and longitude query for the filter.
          def center_query
            if center.kind_of? Atlas::Place
              center_to_search_filter({ :latitude => center.latitude, :longitude => center.longitude })
            elsif center.kind_of? Hash
              center_to_search_filter(center)
            end
          end

          # Takes a hash with :laitude and :longitude and converts it to a search filter query for Solr.
          def center_to_search_filter(center, radius = nil)
            center[:accuracy] ||= 8
            radius = radius || center[:radius] || WHAT_ZOOM_TO_KM[10 - center[:accuracy]]
            "{!spatial lat=#{center[:latitude]} long=#{center[:longitude]} radius=#{radius} unit=km calc=arc threadCount=2}"
          end
          
          # Convert the bounds to a latitude and longitude query for the filter.
          def bounds_to_search_filter(bounds)
            Atlas::Place.spatial_query(bounds)
          end
          
          # Clear out center, bounds, and where values from the query.  Useful for forcing a custom
          # where search around a collection that has a specific location associated with it.  However,
          # if you call this then save the collection, it will wipe out these clauses permanently in
          # the collection!
          def reset_where
            @where = nil
            @center = nil
            @bounds = nil
          end
          
          def blank?
            query.blank? && @sort.blank?
          end
        end
      end
    end
  end
end
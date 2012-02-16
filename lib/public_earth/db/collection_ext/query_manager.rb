module PublicEarth
  module Db
    module CollectionExt
      
      # Manage the query parsing integrating the collections with Solr.
      module QueryManager
        
        def self.included(included_in)
          included_in.extend(ClassMethods)
          included_in.send(:include, InstanceMethods)
        end
                
        module ClassMethods
          
          # Generates a SOLR Search Server formatted query based on the structure
          # of the ruby object passed in as subquery. The ruby object must consist
          # of native ruby data types. In essence, the ruby object is treated as a query
          # tree. In particular hash items AND'd together and Array items are 
          # OR'd together. This is done recursively throughout the entire ruby object. 
          def generate_query(subquery, name=nil, prefix='', tabs='|')
            indent = tabs + " "

            boost = ''
            if match = name.to_s.match(/(.*)(\^[1-9][0-9]*)/)
              name = name.to_s.sub(/(\^[1-9][0-9]*)/, '')
              boost = match[2]
            end

            # Check for overridden operation, stored in name and structure
            if name.to_s.starts_with?('any_')
              name = name.to_s.split(/_/).pop
              op = :or
            elsif name.to_s.starts_with?('all_')
              name = name.to_s.split(/_/).pop
              op = :and
            end

            #puts <<-STR
      #{indent}---------------------------------------------
      #{indent}Type: #{subquery.class}
      #{indent}Name: #{name}
      #{indent}Query: #{subquery.inspect}
            #STR


            if subquery.kind_of?(Array) # OR elements      
              op ||= :or
              query_parts = subquery.map { |part| generate_query(part, name, prefix + prefix_for_name(name.to_s), tabs + "\t|") }

            elsif subquery.kind_of?(Hash) # AND elements
              op ||= :and
              query_parts = subquery.keys.inject([]) do |ret, key| 
                ret << generate_query(subquery[key], key, prefix + prefix_for_name(name.to_s), tabs + "\t|") # key becomes name
              end

            else # return search element (i.e. category:"Restaurants")
              if name.blank?
                return subquery + boost
              else
                return prefix + alternate_name_for(name).to_s.singularize + ":\"#{subquery}\"" + boost
              end
            end

            #puts "#{indent}--------------------------------------------"
            #puts "#{indent}"
            #puts "#{indent}>>>> Generating #{op.to_s.upcase} query from #{query_parts.length} parts."

            if op == :or
              #puts "#{indent}<<<< Returning " + '(' + query_parts.join(' || ') + ')'
              if query_parts.length == 1
                return query_parts.shift + boost
              else
                return '(' + query_parts.join(' || ') + ')' + boost
              end
            elsif op == :and
              #puts "#{indent}Returning " + '(' + query_parts.join(' && ') + ')'

              if query_parts.length == 1
                return query_parts.shift + boost
              else
                return '(' + query_parts.join(' && ') + ')' + boost
              end
            end
          end

          # Some elements have a prefix associated with them in the search. Use
          # this method to ensure that leaf nodes in the search query have the 
          # the proper prefix when they get rendered. 
          # For example, all attributes must be prefixed with "attr_text_". As such
          # any leaf nodes encountered under the :attribute node will be prefixed.
          #
          # If multiple prefixes are specified, they will be applied in depth-first
          # order meaning leaf node prefixes will be the cloest to the actual name
          # and each node up the JSON hierarchy will be prefixed.
          def prefix_for_name(name)
            case name.to_s.downcase.singularize
            when 'attribute': 'attr_text_'
            else ''
            end
          end

          # Some elements in the JSON search query have different names in the
          # search index. When an element gets rendered into the search query
          # this method will be invoked giving you the opportunity to provide
          # an alternative.
          def alternate_name_for(name)
            case name.to_s.downcase.singularize
            when 'place': 'id'
            when 'category': 'belongs_to'
            else name
            end
          end

          # The bounding box filter query is determined as follows: 
          # 
          #   1) if our internal database contains a bounding box for the textual location
          #   specified, just return that. This usually occurs because we want to override
          #   whatever bounding box would be returned by Google LocalSearch.
          #
          #   2) if no location is found in our internal database (likely), attempt a 
          #   Google LocationSearch for the textual location, passing in "nearby"
          #   bounds based off the specified bounding box. 
          #
          #   If no bounding box is specified, the search is still performed, just
          #   with less context (i.e. "Paris" will return "Paris, France" even though 
          #   you might have intended "Paris, TX")
          #
          #   3) No textual location is provided, and the bounding box will be converted
          #   to a filter query string and returned.
          #
          #   4) no information is provided, and nil is returned (not the preferred use).
          #
          def lookup_bounding_box(location, bounds=nil)
            # 4) Garbage In, Garbage Out
            return nil if location.blank? && bounds.blank?

            # 3) Simple Conversion -> Bounding box to filter query
            return "search_longitude:[#{bounds[:sw][:longitude]} TO #{bounds[:ne][:longitude]}] && " +
                     "search_latitude:[#{bounds[:sw][:latitude]} TO #{bounds[:ne][:latitude]}]" if location.blank?

            # 1) Attempt to look up bounding box in the Where search index, trumps all
            where_results = PublicEarth::Where.bounds(location)
            if where_results
              return "search_longitude:[#{results[:sw][:longitude]} TO #{results[:ne][:longitude]}] && " +
                "search_latitude:[#{results[:sw][:latitude]} TO #{results[:ne][:latitude]}]"
            end

            # 2) If that fails, look it up with LocalSearch
            results = PublicEarth::LocalSearch.where(location, nearby(bounds))

            unless results.empty? || results.first.nil?
              where = results.first
              where_alternatives = results[1,-1]

              swx = where[:longitude] - ZOOM_TO_LL[10 - where[:accuracy]]
              swy = where[:latitude] - ZOOM_TO_LL[10 - where[:accuracy]]
              nex = where[:longitude] + ZOOM_TO_LL[10 - where[:accuracy]]
              ney = where[:latitude] + ZOOM_TO_LL[10 - where[:accuracy]]

              return "search_longitude:[#{swx} TO #{nex}] && search_latitude:[#{swy} TO #{ney}]"
            end

            return nil
          end

          # Calculate a bounding box for nearby queries, based on 
          def nearby(bounds)
            nearby = nil
            begin
              nearby = center(@bounding_box)
              nearby[:span_latitude] = (@bounding_box[:ne][:latitude].to_f - @bounding_box[:sw][:latitude].to_f).abs
              nearby[:span_longitude] = (@bounding_box[:ne][:longitude].to_f - @bounding_box[:sw][:longitude].to_f).abs
            rescue
              nearby = nil
            end
          end

          # Calculate the center of the bounding box, returning a hash of :latitude, :longitude
          def center(bounding_box)
            { 
              :latitude => (bounding_box[:sw][:latitude].to_f + bounding_box[:ne][:latitude].to_f) / 2.0,
              :longitude => (bounding_box[:sw][:longitude].to_f + bounding_box[:ne][:longitude].to_f) / 2.0,
            }
          end
          
        end # module ClassMethods
        
        module InstanceMethods
        
          # Generate the Solr query from this collection to return a set of places.
          def to_search_query
            PublicEarth::Db::Collection.generate_query(self.what_object['query'])
          end 

          def to_filter_query(base=nil)
            if base && self.what_object['filter_query']
              [base, "(" + PublicEarth::Db::Collection.generate_query(self.what_object['filter_query']) + ")"].join(" && ")
            elsif self.what_object['filter_query']
              PublicEarth::Db::Collection.generate_query(self.what_object['filter_query'])
            else
              base
            end
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
          def find_places(options = {})
            results = PublicEarth::Db::Place.search_for to_search_query,  
                :start => options[:start] && options[:start].to_i || 0,
                :sort => options[:sort], 
                :fq => to_filter_query(options[:where] || @attributes[:where] || nil, options[:bounds]),
                :qt => 'standard',
                :rows => options[:rows] && options[:rows].to_i > 0 && options[:rows].to_i <= 100 && options[:rows].to_i || 100
            results.models
          end

          def update_what_where
            self.where = @what_object.where || ''
            self.what = @what_object.as_json
          end
          
          def what_object
            @what_object ||= QueryDetails.new(@attributes[:what])
            update_what_where
            @what_object
          end

          def what_object=(value)
            what_object.reset(value)
            update_what_where
            value
          end

        end # module InstanceMethods
      end
    end
  end
end

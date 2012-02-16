module PublicEarth
  module Db
    module CollectionExt
      module QueryManager
        
        # Manages the "query", collecting fields and subqueries into manageable objects that you can manipulate
        # in the code (controllers, models, etc.).  Supports ingesting and expelling JSON versions of the 
        # query, as well as producing Solr-compatible search queries from the Query.
        #
        # Query is a recursive class, in that a Query may contain not only QueryFields, but Query subqueries
        # as well.  
        # 
        # A query has an operation associated with it that informs the output formats how to join the fields and 
        # subqueries together, either :all (and), or :any (or).
        class Query
  
          attr_reader :subqueries, :operation
  
          # Create a new query details manager.  To populate the Query from a JSON object, just pass that JSON
          # object in; otherwise the query will be empty.
          def initialize(json = nil)
            @operation = :any
            @subqueries = []
            parse(json) unless json.blank?
          end

          # Parse the JSON to populate the query.  This is used by the constructor; you shouldn't have to call
          # this directly.
          def parse(json)
            if json.kind_of?(Array)
              @operation = :any
              json.each do |entry|
                if entry.kind_of?(Array)
                  self << Query.new(entry)
                elsif entry.kind_of?(Hash)
                  parse_hash(entry)
                end
              end
            elsif json.kind_of?(Hash)
              @operation = :all
              parse_hash(json)
            end
          end
          
          def parse_hash(entry)
            entry.each do |key, value|
              self << QueryField.new(key) << value if value.present?
            end
          end
          
          # Set the operation for this query, either :all or :any.  Defaults to :any.
          def operation=(value)
            raise "You may not indicate an :all operation on a query with both fields and subqueries!" if value == :all and mixed_query?
            @operation = value == :all && :all || :any
          end
  
          # Look for the given field and return it.  
          #
          # The field should be the name of the field and any modifiers, e.g. "categories", or "all_places^2.0".
          # Modifiers are required for match, e.g. "categories^2.0" will not match "categories", but 
          # "any_categories^1.0" will, as "categories" implies "any_categories^1.0"
          #
          # This method will only search for fields directly in this query; it won't dive into subqueries.
          # Use the find method for that.
          #
          # Returns a QueryField or if it doesn't exist, returns nil.  
          def[](field)
            temporary_field = QueryField.new(field)
            @subqueries.find { |subquery| temporary_field.matches(subquery) }
          end
          
          # Add the given field name to this query by creating a new QueryField and returning it.  If the field
          # already exists, return the existing one.
          def add(field)
            existing = self[field]
            unless existing
              existing = QueryField.new(field)
              @subqueries << existing
            end
            existing
          end
          
          # Update the given field.  If it doesn't exist, it is created.  If it does exist, the values are
          # replaces by the given set of values.  Accepts either a single value, or an array of values.
          #
          # The field should be the name of the field and any modifiers, e.g. "categories", or "all_places^2.0".
          # Modifiers are required for match, e.g. "categories^2.0" will not match "categories", but 
          # "any_categories^1.0" will, as "categories" implies "any_categories^1.0"
          #
          # This method will attach the field directly to this query.
          #
          # Returns the values passed in.
          def[]=(field, values)
            temporary_field = QueryField.new(field)
            existing = @subqueries.find { |subquery| temporary_field.matches(subquery) }
            if existing
              existing.clear
              existing.add(values)
            else
              self << temporary_field
              temporary_field.add(values)
            end
            values
          end
  
          # Look for the given field in all the query field and queries attached to this query.  Recursive.
          # Returns nil if the field could not be found.  Matches not only on name, but boost and operation
          # too.  If name is the same but boost or operation is different, it does not match.
          #
          # Returns the first match.  
          def find(field)
            details = QueryField.parse_key(field)
    
            # The [] method only looks at the current level; it doesn't go deep.
            found = self[field]
    
            # Now look inside Query objects that belong to this Query, if we didn't find a match at this level
            unless found
              @subqueries.each do |subquery|
                # Dive! Dive! Dive!
                found ||= subquery.find(field) if subquery.kind_of? Query
              end
            end
            found
          end

          # Add a query field (QueryField) or a subquery (Query) to this query.  Returns the subquery, for 
          # chaining requests onto that subquery.
          def<<(subquery)
            raise "You may only add a query or a query field!" unless subquery.kind_of?(Query) || subquery.kind_of?(QueryField)
            raise "You may not add subqueries to a query declared with an operation of :all" if @operation == :all && subquery.kind_of?(Query)
             
            existing = subquery.kind_of?(QueryField) && self[subquery.name_as_hash_key] || nil
            if existing
              existing << subquery.values
            else
              @subqueries << subquery 
            end
            
            subquery
          end
  
          # Does the query contain any subqueries?
          def contains_queries?
            !(@subqueries.find { |sq| sq.kind_of? Query }).nil?
          end
          
          # Does the query contain any QueryFields?
          def contains_fields?
            !(@subqueries.find { |sq| sq.kind_of? QueryField }).nil?
          end 
          
          # Does the query contain both Query objects and QueryFields?
          def mixed_query?
            contains_queries? && contains_fields?
          end
          
          # Convert the any or all status to && or ||, for the search query.
          def operation_as_join
            @operation == :all && ' && ' || ' || '
          end
  
          # Build a Solr-compatible search query based on this query.
          def to_query
            (@subqueries.map { |sq| sq.to_query }).join(operation_as_join)
          end

          # Generate a JSON representation of the query.  This is what we store this information as.
          def to_json(*a)
            case @subqueries.length
            when 1: @subqueries.first.to_json
            when 0: nil
            else 
              if @operation == :all
                hash = {}
                @subqueries.each { |sq| hash[sq.name_as_hash_key] = sq.values }
                hash.to_json
              else
                @subqueries.to_json
              end
            end
          end
  
          # Returns the JSON object for this query.
          def to_s
            to_json
          end
  
          # Returns true if there aren't any fields or subqueries in this query.
          def blank?
            (@subqueries.find { |sq| !sq.blank? }).blank?
          end
  
        end
      end
    end
  end
end


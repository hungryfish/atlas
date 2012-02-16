module PublicEarth
  module Db
    module CollectionExt
      module QueryManager
        
        # Manages a search query "field", such as "places" or "categories".  A list of values is associated
        # with the field, and these are submitted to the search engine as either :all (and) or :any (or)
        # operations.
        #
        # Boost may also be injected, either by declaration or by passing in the caret ("^") notation into 
        # the query field name.  Operation may be declared uniquely, or prepended to the name, e.g. 
        # "all_categories^2.0".  This makes it easier to parse the JSON, as it allows the JSON hash key to
        # simply be passed into the constructor without prior manipulation.
        #
        # "Any" (or) is the default operation to query for values.
        class QueryField 
          include Enumerable
          
          attr_accessor :name, :boost, :operation, :values
          
          # Map the field name to something meaningful in the search query, e.g. place -> id.
          def self.mapping(name)
            case name.downcase.singularize
            when 'feature': 'feature'
            when 'mood': 'mood'
            when 'place': 'id'
            when 'category': 'belongs_to'
            when 'keyword': 'search_keyword'
            when 'rating': 'ratingSort'
            when 'source': 'contributor'
            else name
            end
          end
          
          # Take a JSON-based key for a search field, such as all_categories^2.5, and break it apart into
          # the :operation, :name, and :boost.  Returns a hash containing those values.
          #
          # In the above example, you'd receive:
          #
          #   { :operation => :all, :name => 'categories', :boost => 2.5 }
          #
          def self.parse_key(name)
            name.to_s =~ /(?:(any|all)_)?([\w]+)(?:\^([\d\.]+))?/
            { :operation => $1 && $1.to_sym || :any, :name => $2 && $2.downcase || nil, :boost => $3 && $3.to_f || 1.0 }
          end
          
          # You can indicate an "operation", either to return :all results or return :any results in the
          # array.  Boost can be separated by this as well, so that you can boost some items for :any, and
          # some for :all.
          #
          # The name attribute may also be a JSON-based string, in which case boost and operation will be
          # parsed out of it.  Note that specifically declaring boost and operation will override what is in
          # the name string.  
          #
          #   QueryField.new("all_categories^2.0") -> operation = :all, name = "categories", boost = 2.0
          #   QueryField.new("categories^3.0", 1.0, :all) -> operation = :all, name = "categories", boost = 1.0
          #
          # Defaults to a boost of 1.0, and the operation :any.
          def initialize(name, boost = nil, operation = nil)
            parsed = QueryField.parse_key(name)
            @name = parsed[:name]
            @boost = boost && boost.to_f > 0 && boost.to_f || parsed[:boost]
            @operation = operation && operation == :all && operation || parsed[:operation]
            @values = []
          end

          # Attach a value to this field, with the default boost of 1.0.  Returns this field so you can 
          # chain additions, e.g. query['category'] << "dog" << "cat" << "mouse".
          def <<(value)
            add(value)
          end
          
          # Remove the given value from every possible boost of this field name.  Returns this field so you 
          # can chain deletions.
          def >>(value)
            remove(value)
            self
          end
            
          # Attach a value to this field, with the given boost.  If it's already there, the value is not 
          # added again.  
          #
          # If you pass in an array of objects, cycles through and adds each one individually to this field.
          #
          # Returns this field, so you can chain additions.
          def add(value)
            if value.kind_of? Array
              value.each { |v| add(v) }
            else
              value = PublicEarth::Db::Base.as_id(value)
              value = value.id if value.is_a? Atlas::Place
              value.strip! if value.kind_of? String
              @values << value unless @values.include? value
            end
            self
          end
          
          # Remove the given value from this field.  If it's not there, the request is ignored.
          #
          # WATCH OUT!  This method returns the deleted value.  No chaining here!
          def remove(value)
            if value.kind_of? Array
              value.each { |v| remove(v) }
            else
              value = PublicEarth::Db::Base.as_id(value)
              value = value.id if value.is_a? Atlas::Place
              value.strip! if value.kind_of? String
              @values.delete(value)
            end
          end
          
          # Remove all existing values for this field.
          def clear
            @values.clear
          end
          
          # For enumerable...
          def each
            @values.each { |value| yield value }
          end
          
          # Generate the boost portion of the key.
          def boost_as_string
            @boost > 0 && @boost != 1.0 && "^#{@boost}" || ''
          end
          
          # Generate the operation portion of the key, for JSON.
          def operation_as_string
            @operation == :all && 'all_' || ''
          end
          
          # Generate the operation portion of the key, for Solr.
          def operation_as_join
            @operation == :all && ' && ' || ' || '
          end
          
          # For the hash, json, etc.
          def name_as_hash_key
            operation_as_string << @name << boost_as_string
          end
          
          # For the Solr query builder.
          def name_as_search_key
            QueryField.mapping(@name)
          end
          
          # Convert this field to a Hash object.  Used by the JSON generator.
          def to_hash
            { name_as_hash_key => @values }
          end
          
          # Convert this field to JSON, for storage.
          def to_json(*a)
            to_hash.to_json
          end
          
          # Generate the piece of the Solr-compatible query for this field.
          def to_query
            "(#{(@values.uniq.map { |value| "#{name_as_search_key}:\"#{value}\"#{boost_as_string}" }).join(operation_as_join)})"
          end

          # Look to see if the given field is the same "key" as this one.  Matches on name, operation, and boost,
          # but not value.  Useful for finding a QueryField in an array.
          def matches(other)
            other.kind_of?(QueryField) && other.name == @name && other.operation == @operation && other.boost == @boost 
          end
          
          # Not only do the name, operation, and boost have to match, but the list of values as well.
          def ==(other)
            matches(other) && @values == other.values
          end
          
          # How many values are associated with this field?
          def length
            @values.length
          end
          
          # Returns true if no values are associated with this field.
          def blank?
            @values.blank?
          end
          
        end
      end
    end
  end
end

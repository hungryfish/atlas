require 'uuidtools'

module PublicEarth
  module Db
  
    # Holds a connection to the database, much like an ActiveRecord::Base, but also helps out with 
    # calling and processing the stored procedures remotely, through the proxy database.
    class Base
    
      include PublicEarth::Db::Helper::StateMonitor
      include PublicEarth::Db::Helper::Validations
      include PublicEarth::Xml::Helper
      
      extend PublicEarth::Db::Helper::FinderBuilder
      extend PublicEarth::Db::Helper::Relations
      extend PublicEarth::Db::Helper::PredefineAttributes
      extend PublicEarth::Db::Helper::GeneralFind
      
      # The last exception raised in confidence
      attr_reader :exception
      
      # For inherited classes...
      module ClassMethods
        
        def cache_manager
          @cache_manager ||= PublicEarth::Db::Base.base_cache_manager
        end
        
        def cache_manager=(value)
          @cache_manager = value
        end
        
      end
      
      class << self
        include PublicEarth::Db::Base::ClassMethods
        
        def inherited(base)
          class << base
            extend PublicEarth::Db::Base::ClassMethods
          end
        end
        
        # Return the database connection to the proxy.  By default, returns the same value as defined
        # in ActiveRecord::Base.
        def connection
          ActiveRecord::Base.connection
        end
    
        # Run a transaction around the block. This is a no-op if already 
        # inside a transaction.
        def transaction(options={}, &block)
          connection.transaction(options.update(:requires_new => true), &block)
        end
      
        def logger
          ActiveRecord::Base.logger
        end
      
        # Escape the single quotes from your string for SQL, i.e. turn ' into ''
        def escape_quotes(unfiltered)
          unfiltered.to_s.gsub(/'/, "''")
        end
      
        # Helper method to query the stored procedures.  Converts the stored_procedure_call to a
        # simple SELECT statement.  For example:
        #
        #   call('tag.create', "dog")
        #
        # becomes
        #
        #   select * from tag.create('dog');
        #
        # Will escape the attributes for you as well, so don't worry about apostrophes.
        def call(stored_procedure_call, *attributes)
          connection.select_all generate_sql_query(stored_procedure_call, *attributes)
        end

        # Same as call, but instead of returning an array of record hashes, returns a single 
        # record hash.
        def call_for_one(stored_procedure_call, *attributes)
          call(stored_procedure_call, *attributes).first
        end
      
        def one
          @one ||= PublicEarth::Db::One.new(schema_name)
        end
      
        def many
          @many ||= PublicEarth::Db::Many.new(schema_name)
        end
      
        # Extract the generation of the SQL query so we can test its validity
        def generate_sql_query(stored_procedure_call, *attributes)
          sql_query = 'select * from '
          sql_query << stored_procedure_call << '('

          sql_query << attributes.map  { |attribute|
            if attribute.kind_of?(Fixnum) || attribute.kind_of?(Float) || attribute.kind_of?(TrueClass) || 
                attribute.kind_of?(FalseClass)
              attribute
            elsif attribute.nil?
              "null"
            else
              "'" + escape_quotes(attribute) + "'"
            end
          }.join(', ')

          sql_query << ');'
        end
        
        # Since almost everything has an ID, let's just give this one by default.  Also serves as an example for 
        # other finders.
        def find_by_id!(id)
          new(one.find_by_id(id) || raise(RecordNotFound, "A #{name} record for #{id} does not exist."))
        end
        
        # Perform the find query, but return nil instead of raising an exception.
        def find_by_id(id)
          results = one.find_by_id_ne(id)
          results && new(results) || nil
        end

        # Generate a globally unique, random token.
        def generate_token
          UUIDTools::UUID.random_create.to_s
        end
      
        def schema_name
          self.name =~ /::([^:]*)$/ && $1 && ActiveSupport::Inflector.underscore($1) || nil
        end
        
        # Return the cache manager.  If you call this before configuring the cache manager manually,
        # it will create a hash-based cache manager and use that instead of memcache or the database.
        def base_cache_manager
          @cache_manager ||= PublicEarth::Db::MemcacheManager.new
        end

        # You must set the cache manager, or the default Hash based manager will be used.
        def base_cache_manager=(manager)
          @cache_manager = manager
        end

        # Wrap this around a statement to create a local, in-memory cache of the resulting value.  Creates
        # an in-memory hash based on the key_name, storing all the keyed values in it.  For example:
        #
        #   def self.find_by_name(name)
        #     cache_locally :by_name => name do
        #       construct_if_found one.find_by_name(name)
        #     end
        #   end
        #
        # This will create a @@cached[:by_name] = { name => result } hash in the class.  The first time
        # called for a name like "sample", we'll ask the database for the information.  The next time, we'll
        # pull it from @@cached[:by_name]['sample'].
        def cache_locally(key_hash, &block)
          @cached ||= Hash.new { |hash, key| hash[key] = {} }
          
          key_name = key_hash.keys.first
          key = key_hash[key_name]
          
          @cached[key_name.to_sym][key] ||= block.call(key)
        end
        
        def local_cache
          @cached
        end
        
        # Convert an object to an ID, if you're expecting an ID and you've got a PublicEarth::Db::Base
        # object.
        def as_id(object)
          object.kind_of?(PublicEarth::Db::Base) && object.id || object
        end
        
        # Take the results, and if they're not nil or empty, construct a new object out of them.  If
        # the are empty, just return nil.  This is use for queries on the database that it's o.k. if
        # they don't return a result, but we don't want them to create an empty object either.
        #
        # Classes like Category and Attribute use this in the caching process, as well as when testing
        # various attribute lookups (plural versus singluar).
        def construct_if_found(results)
          unless results.blank?
            new(results)
          else
            nil
          end
        end
      end # ClassMethods
    
      def initialize(attributes = {})
        @attributes = {}
        self.attributes = attributes
        clear_state
        
        # TODO:  Temporary, to handle "exists" state; we should be more thorough, perhaps...
        exists if id
      end
    
      def id=(value)
        @attributes[:id] = value || nil
      end
    
      def id
        @attributes[:id]
      end
    
      # Compare objects for equality by their attributes.
      def ==(other)
        other.present? && self.attributes == other.attributes
      end
  
      # Return the attribute value for this record.  The key can be either a symbol or a string.
      def read_attribute(key)
        @attributes[key.to_sym]
      end
      alias :[] :read_attribute

      def write_attribute(key, value)
        unless value == @attributes[key.to_sym]
          @attributes[key.to_sym] = value
          self.changed
        end
        @attributes[key.to_sym]
      end
      alias :[]= :write_attribute
  
      def attributes
        @attributes
      end
  
      # Apply the set of attributes given to the attributes associated with this record.  Replaces
      # existing values that have been updated, but does not remove any existing attribute values
      # that are not in the supplied updated_attributes hash.
      def attributes=(updated_attributes)
        updated_attributes.each do |key, value|
          @attributes[key.to_sym] = value
        end if updated_attributes
        @attributes
      end
  
      alias :default_method_missing :method_missing
      
      # TODO:  Add ? method for booleans
      # TODO:  Generate actual methods?  Better performance...
      def method_missing(method_name, *args)
        # Return the attribute value
        if @attributes.has_key?(method_name)
          read_attribute(method_name)
        
        # If we predefine an attribute, but we don't have it loaded, return nil
        elsif self.class.predefined_attributes.include?(method_name)
          nil
          
        # Check booleans, attribute_name?
        elsif method_name.to_s =~ /\?$/
          simple_method_name = method_name.to_s.gsub(/\?$/, '').to_sym
          @attributes[simple_method_name] == true || @attributes[simple_method_name] == 't' || 
              @attributes[simple_method_name] == 'true'
          
        # Method to set attribute, attribute_name=
        elsif method_name.to_s =~ /=$/ && !args.empty?
          write_attribute(method_name.to_s.gsub(/=$/, '').to_sym, args.first)
          
        # Default to raising an error
        else
          default_method_missing(method_name, *args)
        end
      end
    
      def connection
        PublicEarth::Db::Base.connection
      end

      def escape_quotes(unfilterd)
        PublicEarth::Db::Base.escape_quotes(unfiltered)
      end

      # Expects the extending class to have a to_xml method that returns a Ruby LibXML XML::Node
      # object, which will then be wrapped in a generic XML::Document and returned.  Useful if
      # you care enough to send only one of an object!
      def xml_document
        xml = XML::Document.new
        xml.root = self.to_xml
        xml
      end
      
      # Convert the object to an Apple PropertyList.  Does not have the XML document wrapper, in
      # case you want to include it as part of an array or other objects.
      def to_plist
        @attributes.to_plist
      end
    
      def logger
        PublicEarth::Db::Base.logger
      end
      
      def cache_manager
        PublicEarth::Db::Base.cache_manager
      end
      
      # This method does nothing.  Your model class should implement this and use it to wipe any collection
      # caches, like all the categories or all the attributes, and then to update the cache with information
      # about an object.  The method will be called after the model has been updated.
      def update_cache
        # Does nothing...up to subclasses to implement.
      end
      
      # The query_for method is a lazy loading tool.
      #
      # Sets the attribute value equal to the results of the block if the attribute is blank.  Otherwise
      # returns the attribute value.  Also handles updating the cache if the value has to be loaded.  
      #
      # The attribute should be a symbol for the variable name, e.g. :parents for the @attributes[:parents] variable.
      #
      # Returns the value of the attribute.
      def query_for(attribute, &block)
        unless loaded? attribute
          assign attribute, block.call
        end
        @attributes[attribute]
      end
      
      # Update the information about the attribute (as a symbol).  The "get" to query_for's "set".  Similar to
      # write_attribute in Rails.
      def assign(attribute, value)
        @attributes[attribute.to_sym] = value
      end
      
      # Set the attribute for nil.  Works with query_for so that the attribute will be pulled from the database
      # or memcache next time it is requested.
      def reset(attribute)
        @attributes.delete attribute.to_sym
      end
      
      # Is the requested attribute present in the list of @attributes, i.e. has it been loaded yet?
      def loaded?(attribute)
        !@attributes[attribute.to_sym].blank?
      end
      
      # Send in a block with this, and this method will call the block, trap the exception, assign
      # it to the @exception instance variable, and return either true or false at sucess or failure.
      def trap_exception
        begin
          yield
          true
        rescue
          @exception = $!
          false
        end
      end
      
    end
  
    class RecordNotFound < StandardError; end
    class CreateFailed < StandardError; end
    class DeleteFailed < StandardError; end
  
  end
end

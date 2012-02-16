module PublicEarth
  module Db
    
    # Manage attribute definitions in the database, for category properties.
    class Attribute < PublicEarth::Db::Base
      
      class Selection
        attr_accessor :id, :category, :value, :language
        
        def initialize(attributes)
          @id = attributes['id']
          @category_id = attributes['category_id']
          @value = attributes['value']
          @language = attributes['language']
        end
      end
      
      class << self
        
        # Loads just the basic attribute definition.
        def find_by_id!(id)
          cache_manager.ns(:attributes).get_or_cache(id, 24.hours) do 
            new(one.find_by_id(id))
          end
        end
        
        # Loads just the basic attribute definition information.
        def find_by_id(id)
          cache_manager.ns(:attributes).get_or_cache(id, 24.hours) do 
            construct_if_found one.find_by_id_ne(id)
          end
        end

        # Loads just the basic attribute definition.
        def find_by_name!(name)
          cache_locally :by_name => name do
            cache_manager.ns(:attributes_by_name).get_or_cache(name, 24.hours) do 
              new(one.find_by_name(name))
            end
          end
        end
        
        # Loads just the basic attribute definition information.
        def find_by_name(name)
          cache_locally :by_name => name do
            cache_manager.ns(:attributes_by_name).get_or_cache(name, 24.hours) do 
              construct_if_found one.find_by_name_ne(name)
            end
          end
        end
        
        # Create a new attribute definition.  If you call this for an existing definition, it will return
        # the existing definition instead, without creating a new one.  However, if you try to change the
        # data type of the attribute definition, this method will raise an exception.
        def create(name, data_type = nil)
          new(one.create(name, data_type) || raise(CreateFailed, "Unable to create an attribute definition for #{name}."))
        end
      
        # Indicate the suggested, possible choices we could use for this attribute.  There is nothing
        # restricting in the data models that requires these values; they're optional.
        def set_selections(name, selections) 
          one.set_selections(name, "{#{selections.join(',')}}")
        end
        
        # Convert an array of record hashes from the database into a collection of attribute definition
        # objects.
        def attributes_hash_from_records(records)
          Hash[*records.map { |record| [record['name'], new(record)] }.flatten]
        end
      
        # Change the priority of an attribute.  Used by the Ontology priority loader.
        def priority(category_id, attribute_name, priority)
          new(one.priority(category_id, attribute_name, priority) || raise(RecordNotFound, 
              "Unable to update the attribute #{attribute_name} priority for category #{category_id}."))
        end
        
        # Return all the attributes in the database, regardless of category.  Also caches every attribute.
        def all

            cache_manager.ns(:attributes).get_or_cache(:all, 24.hours) do
              all = many.definitions.map {|results| new(results)}
              all.each do |attribute|
                cache_manager.ns(:attributes).get_or_cache(attribute.id, 24.hours) { attribute }
                cache_manager.ns(:attributes_by_name).get_or_cache(attribute.name, 24.hours) { attribute }
              end
            end

        end
        
        # HACK!  This retrieves the grouped list of possible features that user should be able to 
        # set the features attribute to.
        def features

            cache_manager.ns(:attributes).get_or_cache(:features, 24.hours) do
              features = Hash.new { |hash, key| hash[key] = [] }
              PublicEarth::Db::Attribute.many.features.each do |feature|
                features[feature['collection']] << feature['feature']
              end            
              features
            end            

        end
        
        # Call this to reset general caches of categories, like the set of all the categories, or the assignable
        # categories.
        def reset_cache
          cache_manager.ns(:attributes).delete(:all)
          cache_manager.ns(:attributes).delete(:features)
          reset_local_cache
        end
        
      end # class << self
      
      # Call this whenever attributes are modified to reset the cache collections of attributes (:all, etc.)
      # and also update this object's information in the cache.  Returns self.
      def update_cache
        PublicEarth::Db::Attribute.reset_cache
        cache_manager.ns(:attributes).put(self.id, self, 24.hours)
        cache_manager.ns(:attributes_by_name).put(self.name, self, 24.hours)
      end
      
      # Get the optional selections associated with this attribute.
      def selections
        query_for :selections do
          PublicEarth::Db::Attribute.many.selections(self.name).map { |s| PublicEarth::Db::Attribute::Selection.new(s) }
        end
      end

      # Does this attribute accept many values, e.g. features.
      def allow_many?
        @attributes[:allow_many] == 't'
      end
      
      def to_xml
        xml = XML::Node.new('attribute')
        xml['id'] = self.id
        
        xml << xml_value(:name, self.name)
        xml << xml_value(:label, self.name.to_s.titleize)
        xml << xml_value(:data_type, self.data_type)
        xml << XML::Node.new('allow_many', self.allow_many == 't' && "true" || "false")
        xml << XML::Node.new('readonly', self.allow_many == 't' && "true" || "false")
        
        xml
      end
      
      def to_s
        self.name
      end
    end
  end
end
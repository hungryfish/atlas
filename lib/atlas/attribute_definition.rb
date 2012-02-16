module Atlas
  class AttributeDefinition < ActiveRecord::Base

    has_many :category_attributes, :class_name => 'Atlas::CategoryAttribute'
    has_many :categories, :through => :category_attributes, :class_name => 'Atlas::Category'

    # named_scope :named, lambda { |name|
    #     { :conditions => ["name in (?)", [name.to_s, name.to_s.pluralize]] }
    #   }
      
    class << self
      # TODO:  Deal with the readonly column...
      def instance_method_already_implemented?(method_name)
        method_name =~ /readonly[\?=]?/ && true || super
      end
    end

    # Look up in the cache.  Behaves like a named scope for backwards compatibility.
    def self.named(name)
      results = PublicEarth::Db::Base.cache_manager.ns(:attributes_by_name).get_or_cache(name) do 
        find_by_name(name)
      end
      results.present? && [results] || nil
    end
    
    def to_s
      name
    end
    
    def to_xml
      xml = XML::Node.new('attribute')
      xml['id'] = self.id
      
      xml << xml_value(:name, self.name)
      xml << xml_value(:label, self.name.to_s.titleize)
      xml << xml_value(:data_type, self.data_type)
      xml << XML::Node.new('allow_many', self.allow_many == 't' && "true" || "false")
      #xml << XML::Node.new('readonly', self.allow_many == 't' && "true" || "false")
      
      xml
    end
    
    class Selection < ActiveRecord::Base
      set_table_name "attribute_selections"
    end
      
  end  
end

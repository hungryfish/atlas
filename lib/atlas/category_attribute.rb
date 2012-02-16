module Atlas
  class CategoryAttribute < ActiveRecord::Base
    belongs_to :category, :class_name => 'Atlas::Category'
    belongs_to :definition, :foreign_key => 'attribute_definition_id', :class_name => 'Atlas::AttributeDefinition'
    
    def name
      definition.name
    end
    alias :to_s :name
    
  end  
end

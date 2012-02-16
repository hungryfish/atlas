module Atlas
  class RelatedCategory < ActiveRecord::Base
    belongs_to :category, :foreign_key => 'related_to', :class_name => 'Atlas::Category'
    belongs_to :child_category, :foreign_key => 'category_id', :class_name => 'Atlas::Category'      
  end
end
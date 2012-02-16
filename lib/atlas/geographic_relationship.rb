module Atlas
  class GeographicRelationship < ActiveRecord::Base
  
    belongs_to :subject, :class_name => "Atlas::Geography", :foreign_key => "subject"
    belongs_to :predicate, :class_name => "Atlas::Geography", :foreign_key => "predicate"
  
  end
end
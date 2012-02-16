module Atlas
  class Deletion < ActiveRecord::Base
  
    belongs_to :place, :class_name => 'Atlas::Place', :foreign_key => 'id'
    belongs_to :source, :class_name => 'Atlas::Source', :foreign_key => 'deleted_by_id'
  
    validates_presence_of :place, :source
    
  end
end
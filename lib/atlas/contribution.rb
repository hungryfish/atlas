module Atlas
  class Contribution < ActiveRecord::Base
    set_table_name 'contributors'
    
    belongs_to :source, :class_name => 'Atlas::Source'
    belongs_to :place, :class_name => 'Atlas::Place'
    named_scope :visible, :conditions => {:publicly_visible => true}
  end
end

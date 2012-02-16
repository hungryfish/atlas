module Atlas
  class PlaceTag < ActiveRecord::Base
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :tag, :class_name => 'Atlas::Tag'
    belongs_to :source_data_set, :class_name => 'Atlas::SourceDataSet'
    
    validates_presence_of :place, :tag, :source_data_set
    
  end
end

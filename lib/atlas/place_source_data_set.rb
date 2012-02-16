module Atlas
  class PlaceSourceDataSet < ActiveRecord::Base
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :source_data_set, :class_name => 'Atlas::SourceDataSet'
  
    validates_presence_of :place_id
    validates_presence_of :source_data_set_id
    validates_uniqueness_of :place_id, :scope => :source_data_set_id
  end
end
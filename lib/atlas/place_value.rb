module Atlas
  class PlaceValue < ActiveRecord::Base
    
    belongs_to :place_attribute, :class_name => 'Atlas::PlaceAttribute'
    belongs_to :source_data_set, :class_name => 'Atlas::SourceDataSet'

    def to_s
      value
    end
    
  end
end
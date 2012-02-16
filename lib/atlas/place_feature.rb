module Atlas
  class PlaceFeature < ActiveRecord::Base
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :feature, :class_name => 'Atlas::Feature'
    
    validates_presence_of :place, :feature
    validates_uniqueness_of :feature_id, :scope => :place_id
  end
end
module Atlas
  class PlaceMood < ActiveRecord::Base
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :mood, :class_name => 'Atlas::Mood'
    belongs_to :user, :class_name => 'Atlas::User'
    
    validates_presence_of :place, :mood, :user
    validates_uniqueness_of :user_id, :scope => [:place_id, :mood_id] # only one vote per user per mood per place
  end
end
module Atlas
  class Rating < ActiveRecord::Base
    set_table_name 'source_place_ratings'
    
    belongs_to :source, :class_name => 'Atlas::Source'
    belongs_to :place, :class_name => 'Atlas::Place'
    
    validates_presence_of :source
    validates_presence_of :place 
     
    validates_presence_of :rating
    validates_numericality_of :rating, :only_integer => true, :less_than_or_equal_to => 1, :greater_than_or_equal_to => -1
    validates_uniqueness_of :rating, :scope => [:source_id, :place_id]
    
    before_create :generate_uuid
    
    # Generate a unique ID for this object.
    def generate_uuid
      self.id = UUIDTools::UUID.random_create.to_s
    end
    
    def to_s
      case self.rating
      when -1
        "Dislike It"
      when 0
        "Been there, no opinion"
      when 1
        "Like It"
      end
    end
    
    def to_i
      self.rating
    end
  end
end
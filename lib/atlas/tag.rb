module Atlas
  class Tag < ActiveRecord::Base
    validates_uniqueness_of :name, :case_sensitive => false
    validates_format_of :name, :with => /^[a-zA-Z0-9\-\s]*$/

    def name
      read_attribute(:name).downcase
    end
    
    def name=(value)
      write_attribute(:name, value.downcase)
    end
    
    def to_s
      self.name
    end
  
  end
end

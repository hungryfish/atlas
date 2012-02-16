module Atlas
  class Mood < ActiveRecord::Base
    validates_presence_of :name
    
    def to_s
      self.name
    end
    
    def to_param
      "#{id}-#{name.parameterize}"
    end
  end
end
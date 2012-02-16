module Atlas
  class Feature < ActiveRecord::Base
    has_and_belongs_to_many :categories
    
    def to_s
      self.name
    end
    
    def to_param
      "#{id}-#{name.parameterize}"
    end
  end
end
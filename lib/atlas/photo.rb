module Atlas
  class Photo < ActiveRecord::Base
    belongs_to :place  
  end
end

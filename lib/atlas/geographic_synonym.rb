module Atlas
  class GeographicSynonym < ActiveRecord::Base
  
    belongs_to :geography, :class_name => 'Atlas::Geography'
  
  end
end
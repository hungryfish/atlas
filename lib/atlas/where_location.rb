module Atlas
  class WhereLocation < ActiveRecord::Base
    named_scope :locations_containing_point, lambda {|latitude, longitude|
      { 
        :conditions => "st_setsrid(st_makepoint(#{longitude}, #{latitude}), 4326) && bounds",
        :order => 'st_area(bounds) ASC' 
      }
    }
    
    def [](key)
      if(key == :sw || key == :ne)
        {:latitude => self["#{key}_latitude".to_sym], :longitude => self["#{key}_longitude".to_sym]}
      else
        super(key)
      end
    end
  end
end
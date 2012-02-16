module PublicEarth
  module Db

    class Contributor < PublicEarth::Db::Base
      class << self
        
        def contribute(place, source_data_set)
          one.contribute(as_id(place), as_id(source_data_set))
        end
      
        def schema_name
          'history'
        end

      end # class << self
      
    end
  
  end
end
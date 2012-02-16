module PublicEarth
  module Db

    # Places have many photos.
    class PlacePhoto < PublicEarth::Db::Base

      # Update an existing photo, either uploading a new image (new path) or by changing its caption.  If the
      # path is null or the caption is null, it will not be changed from the original.  If you would like to 
      # remove a caption, set it equal to an empty string.
      def update(path_to_file, caption, data_set)
        @attributes = PublicEarth::Db::Place.one.update_photo(self.id, path_to_file, caption, data_set.id)
      end
      
      def initialize(attributes = {}, place = nil)
        super attributes
        @place = place
      end
    
      def path_to_file(where = :raw)
        case where
        when :html
          @place.html_path_to_photos + @attributes[:path_to_file]
        when :system
          @place.system_path_to_photos + @attributes[:path_to_file]
        else
          @attributes[:path_to_file]
        end
      end

    end
  end
end
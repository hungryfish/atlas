module PublicEarth
  module Db
    module PhotoExt
      module Handlers
        
        class Url
          attr_accessor :photo
  
          def can_handle_photo
            uri = URI.parse(photo.filename)
            return uri.scheme == 'http'
          rescue
            false
          end
  
          def original_photo_url
            photo.filename # filename is already url
          end
          
          def get_formatted_copyright
            photo.attributes[:copyright]
          end

          def get_formatted_caption
            photo.attributes[:caption]
          end
          
        end # end Url
             
      end # end Handlers
    end
  end
end

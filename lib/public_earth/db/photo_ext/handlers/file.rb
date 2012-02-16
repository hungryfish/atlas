module PublicEarth
  module Db
    module PhotoExt
      module Handlers
        
        class File
          attr_accessor :photo
  
          def can_handle_photo
            photo.filename !~ /^http:\/\//
          end
  
          def original_photo_url
            if $cloudfront && $cloudfront[photo.s3_bucket]
              "#{$cloudfront[photo.s3_bucket]}/#{photo.s3_key}"
            else
              "http://#{photo.s3_bucket}.s3.amazonaws.com/#{photo.s3_key}"
            end
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

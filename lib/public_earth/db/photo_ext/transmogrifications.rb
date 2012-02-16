module PublicEarth
  module Db
    module PhotoExt
      
      # Transforms photos into something they shouldn't be.
      module Transmogrifications

        CROP = true
        DONT_CROP = false
        
        # The following transformations are based on Flickr image sizes.
        DEFAULT_TRANSMOGRIFICATIONS = {
          :square => [75, 75, CROP],
          :square_doubled => [150, 150, CROP],
          :map => [124, 84, CROP],
          :details => [394, nil, DONT_CROP],
          :large => [900, nil, DONT_CROP]
          
          # :thumbnail => [100, nil, DONT_CROP],
          # :small => [240, nil, DONT_CROP],
          # :medium => [500, nil, DONT_CROP],
          # :large => [1024, nil, DONT_CROP]
        }
        
        def self.included(included_in) 
          included_in.extend(PublicEarth::Db::PhotoExt::Transmogrifications::ClassMethods)
          included_in.send(:include, PublicEarth::Db::PhotoExt::Transmogrifications::InstanceMethods)
        end
        
        module ClassMethods

          # Returns all the Photo::Modification objects associate with the given photo.
          def modifications(photo)
            photo = PublicEarth::Db::Photo.find_by_id(photo) if photo.kind_of? String
            if photo
              PublicEarth::Db::Photo.many.modifications(photo.id).map do |results| 
                PublicEarth::Db::Photo::Modification.new(results.merge(:photo => photo))
              end
            else
              []
            end
          end

        end

        module InstanceMethods
          
          # Generate all of our default thumbnails and such.
          def generate_default_transmogrifications
            DEFAULT_TRANSMOGRIFICATIONS.keys.each { |name| modify :name => name } #if local?
          end
        
          # Resize the photo to the given width and height.  The photo will be cropped to fit.  If the 
          # height is nil, resizes the height based on the original aspect ratio to the width.  
          #
          # The name indicates what will be added to the root of the filename to save this image locally.
          # For example, if name is "thumbnail" and the file is "test.jpg", the resized file will be saved
          # as "test-thumbnail.jpg".  If you leave off the name, it will be based on the width and height,
          # e.g. "test-120x100.jpg".
          #
          # Requires local_path_to_file to be set and point to a valid file on disk.
          def transmogrify(width, height = nil, name = nil, crop = false)
            download_original unless local?
            if local?
              name ||= "#{width}x#{height}"

              to_transform = Magick::Image.read(self.local_path_to_file).first
            
              if crop && width && height
                to_transform.crop_resized!(width.to_i, height.to_i, Magick::NorthGravity)
              else
                to_transform.change_geometry!("#{width}x#{height}") do |cols, rows, img|
                  if to_transform.columns >= cols
                    img.resize!(cols, rows)
                  end
                  img
                end
              end
            
              file = file_parts
              new_path = "#{file[:path]}/#{file[:root]}-#{name}.#{file[:extension]}"
              to_transform.write new_path
            
              new_path
            end
          end

          # Return the modifications associated with this photo.  
          def modifications
            @modifications ||= PublicEarth::Db::Photo.modifications(self)
          end

          # Look up a modification by its name.  Returns nil if no modification by that name was found.
          def modification(name)
            name = name.to_s
            modifications.find { |modification| modification.name == name }
          end

          # Transmogrify the photo and add it to the modifications array.  You can either declare a 
          # :width and a :height, or declare a :name matching one of the DEFAULT_TRANSMOGRIFICATIONS,
          # in which case the width and height from that will be used.  You may also specify whether or
          # not to :crop the photo to fit the size.  See transmogrify for details.
          #
          # The name indicates what will be added to the root of the filename to save this image locally.
          # For example, if name is "thumbnail" and the file is "test.jpg", the resized file will be saved
          # as "test-thumbnail.jpg".  If you leave off the name, it will be based on the width and height,
          # e.g. "test-120x100.jpg".
          #
          # Requires local_path_to_file to be set and point to a valid file on disk.  
          #
          # Returns the Photo::Modification model representing the transformation.
          def modify(options = {})
            options = options.kind_of?(Symbol) && { :name => options } || options
            
            frog = nil

            # Use one of the defaults?
            if options[:name] && DEFAULT_TRANSMOGRIFICATIONS.keys.include?(options[:name])
              dt = DEFAULT_TRANSMOGRIFICATIONS[options[:name]]
              options[:width] = dt[0]
              options[:height] = dt[1]
              options[:crop] = dt[2]
            end

            # Does a modification with this name already exist
            frog = modification(options[:name])
            if frog
              
              # If the dimensions are the same, we can just update S3 without modifying the database...
              if options[:width].to_i == frog.width.to_i && options[:height].to_i == frog.height.to_i
                frog.local_path_to_file = transmogrify(frog.width, frog.height, options[:name], frog.crop)
                
              # ...otherwise we need to delete this modification and replace it.
              else
                frog.delete!
                frog = nil      # see below...
              end
              
            end
            
            # If the photo doesn't exist or has been deleted, generate a new transmogrified frog.  That's
            # why we set frog to nil above if the original modification (with the same name) needs to be
            # removed.
            if frog.nil?
              frog = PublicEarth::Db::Photo::Modification.new(
                  :photo => self,
                  :crop => options[:crop] || DONT_CROP
                )
              frog.local_path_to_file = transmogrify(options[:width], options[:height], options[:name], options[:crop] || DONT_CROP)
              frog.name = options[:name] && options[:name].to_s || "#{frog.width}x#{frog.height}"

              if frog.local_path_to_file.present?
                modifications << frog
              end
            end
            
            # Flag the photo so we'll update not only the modification, but also modify the photo.updated_at value;
            # only if the frog has been transmogrified.
            changed if frog && (frog.local? || frog.deleted?)
            
            frog
          end

          # Cycle through all the modifications that exist on the photo and update them.  This is called
          # with the path to the photo is change, presumably a new photo is being uploaded.
          def regenerate_modifications
            modifications.each do |frog|
              frog.local_path_to_file = transmogrify(frog.width, frog.height, frog.name, frog.crop)
            end
          end
          
          # Try to save all the modifications (thumbnails, etc.) to the photo.  If any photo save fails,
          # raises an exception.  If no modifications have been loaded, this request is ignored, presuming
          # you're updating a photo that hasn't changed anything about the picture itself.
          def save_modifications!(options)
            unless @modifications.blank?
              PublicEarth::Db::Photo.connection.transaction do
                @modifications.each { |frog| frog.save!(options) }
              end 
            end
          end

          # Try to remove all the modifications (thumbnails, etc.) to the photo.  If any photo delete fails,
          # raises an exception.  
          def clear_modifications!(options)
            unless modifications.empty?
              PublicEarth::Db::Photo.connection.transaction do
                modifications.each { |frog| frog.delete! }
              end 
              modifications.each { |frog| frog.remove_from_s3 }
            end
          end 

        end
      end
    end
  end
end

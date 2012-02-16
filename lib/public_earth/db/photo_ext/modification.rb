require 'public_earth/db/photo_ext/s3_support'

module PublicEarth
  module Db
    class Photo < PublicEarth::Db::Base
      
      # Transformations made to photos such as resizing or styling.  The original photo is stored as
      # a Photo object, with these Transformation object's behind them.
      class Modification < PublicEarth::Db::Base
      
        include PublicEarth::Db::PhotoExt::S3Support
        
        module StoredProcedures

          def self.create(photo_id, filename, s3_key, width, height, crop, name)
            photo_id = photo_id.kind_of?(PublicEarth::Db::Photo) ? photo_id.id : photo_id
            PublicEarth::Db::Photo.one.modify(photo_id, filename, s3_key, width, height, crop, name)
          end

          def self.delete(id)
            PublicEarth::Db::Photo.one.remove_modification(id)
          end

        end # StoredProcedures
      
        class << self

          def schema_name
            'photo'
          end

          # Create a new photo modification in the database.  
          def create(attributes)
            modification = new(attributes)
            modification.save!
          end

        end # class self

        def initialize(attributes = {})
          attributes[:photo] || attributes[:photo_id] || raise("Please indicate the photo or its ID with which to associate this modification.")
          
          super
          calculate_attributes
        end
        
        # Is there a local file associated with this photo?  Typically true in new files, false in ones that
        # have been retrieved from the database.  The local file must be defined and exist on disk.
        def local?
          @attributes[:local_path_to_file] && File.exist?(@attributes[:local_path_to_file])
        end

        # Compute the width, height, size (in KB), when the photo was created (created_at)
        #
        # Will forcibly overwrite width, height, and size, preferring the RMAGICK details over user-indicated
        # information.
        #
        # If there is no local_path_to_file defined, calling this method does nothing.
        #
        def calculate_attributes
          if local?
            file = Magick::Image.read(local_path_to_file).first
            @attributes[:width] = file.columns
            @attributes[:height] = file.rows
            @attributes[:created_at] ||= file.properties['create-date']
          end
        end
        
        # Reset all the attributes related to the physical metadata surrounding the photo, including
        # width, height, size, creation date, latitude, and longitude.  
        def reset_attributes
          @attributes.delete :width
          @attributes.delete :height
          @attributes.delete :created_at
        end

        # Resets the s3_key and all the calculated attributes, including created_at, latitude, and longitude,
        # in expectation the file has changed. 
        def local_path_to_file=(value)
          @attributes[:local_path_to_file] = value
          reset_attributes
          calculate_attributes
          value
        end
        
        # Return the photo associated with the transformation.
        def photo
          @attributes[:photo] ||= PublicEarth::Db::Photo.find_by_id(@attributes[:photo_id])
        end
        
        # Returns the bucket associated with the original photo.
        def s3_bucket
          photo.s3_bucket
        end
        
        # Convert the place ID, photo source ID, the base filename, and the modification name into an S3 key.
        def calculate_s3_key
          if photo && photo.filename && photo.source_id && name
            "places/#{photo.place_id}/#{photo.source_id}/#{photo.file_parts[:root]}-#{name}.#{photo.file_parts[:extension]}"
          else
            nil
          end
        end
        
        # Return the URL for the modification.
        def url
          if @attributes[:filename] =~ /^http:\/\//
            @attributes[:filename]
          elsif $cloudfront && $cloudfront[s3_bucket]
            "#{$cloudfront[s3_bucket]}/#{s3_key}"
          else
            "http://#{s3_bucket}.s3.amazonaws.com/#{s3_key}"
          end
        end
        
        # Raise an exception if the save fails.  You can pass in :skip_s3 => true to skip uploading the 
        # modification to S3.
        def save!(options = {})
          upload_to_s3 unless options[:skip_s3] == true
          
          # If this guy already exists, don't update it.  You can't update a modification, only delete it.
          if self.id.nil?
            filename = "#{photo.file_parts[:root]}-#{@attributes[:name]}.#{photo.file_parts[:extension]}"
            results = StoredProcedures.create(photo.id, filename, s3_key, @attributes[:width], 
                @attributes[:height], @attributes[:crop], @attributes[:name])
            self.id = results['id']
          end
        end
        
        # Returns true if the save was successful, false if not.
        def save(options = {})
          trap_exception { save!(options) }
        end
        
        # Delete this modification.  Does nothing with the file on S3.  Raises an exception if the delete
        # fails.
        def delete!
          StoredProcedures.delete(self.id) if self.id
        end

        # Returns true if the modification could be deleted; false otherwise.
        def delete
          trap_exception { delete! }
        end
        
        def to_hash
          {
            :id => self.id,
            :url => self.url,
            :width => self.width,
            :height => self.height,
            :crop => self.crop == 't' && 'true' || 'false',
            :name => self.name
          }
        end
        
        def to_json(*a)
          to_hash.to_json(*a)
        end
        alias :as_json :to_json
        
        def to_plist
          to_hash.to_plist
        end
        
        def to_xml
          xml = XML::Node.new('modification')
          
          to_hash.each do |key, value|
            xml << xml_value(key, value)
          end
          
          xml
        end
        
      end
    end
  end
end
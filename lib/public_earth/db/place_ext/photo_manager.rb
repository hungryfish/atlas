require 'exifr'

module PublicEarth
  module Db
    module PlaceExt
      
      # Access this through Place.photos...handles the Photo and PhotoModification classes in a 
      # meaningful way, with regards to the Place.  By default behaves like a collection of Photo
      # objects.
      class PhotoManager < Delegator
        attr_reader :place, :exception
      
        # Configures the S3 server and loads the existing place photos from the database.  If our assets bucket
        # doesn't exist, it is created.
        def initialize(place)
          @place = place || raise("Place is required.")
          from_database
          super(@photos)
        end
      
        # For delegator...provides length, find, each, first, last, etc.
        def __getobj__
          photos
        end

        # Retrieve photos from the database for the place associated with this photo manager.
        def from_database
          @photos = PublicEarth::Db::Place.many.photos(@place.id).map { |result| PublicEarth::Db::Photo.new(result) }
        end
      
        # Indicate who is going to be modifying these photos.  You may pass in a PublicEarth::Db::User object,
        # a PublicEarth::Db::Source object, or a source ID (string). 
        def from(source)
          if source.kind_of? Atlas::User
            source = source.source
          end
          @data_set = source.source_data_set
          @working_source = source.kind_of?(String) && PublicEarth::Db::Source.find_by_id(source) || source
        end

        # Raises an exception if the working_source has not been set.  Used internally by methods that need 
        # a valid source.
        def working_source?
          raise "Please indicate the source of this information by calling the from() method with a source object." if @working_source.nil?
        end
      
        # Add a new photo.  If you pass in a string or File object, assumes it is the local path to the photo
        # file, and wraps it in a new Photo class.  If the attribute passed in is a Photo, adds it to the 
        # array managed by the PhotoManager.
        #
        # Returns the Photo object.
        def add(photo)
          working_source?
          photo = File.expand_path(photo.path) if ( photo.kind_of?(File) || photo.kind_of?(Tempfile) )
        
          if photo.kind_of? String
            if File.exist?(photo)
              photo = PublicEarth::Db::Photo.new(
                  :place_id => @place.id, 
                  :source_id => @working_source.id,
                  :local_path_to_file => photo)
            else
              raise "File not found: #{photo}"
            end
          elsif photo.kind_of?(PublicEarth::Db::Photo)
            photo.place_id = @place.id
            photo.source_id = @working_source.id
          end
        
          # See if the photo already exists...
          existing = @photos.find { |check| photo == check }

          unless existing
            photo.changed
            @photos << photo
          else
            existing.update_from(photo)
            photo = existing
          end
        
          photo
        end
      
        # Remove the given photo object from the collection.  Will delete it from the database when the 
        # manager is saved.  Only a source may remove its files.
        def remove(photo)
          working_source?
        
          @photos.each do |check|
            check.deleted if check == photo
          end
        end
        
        # Return all the photos managed by this object.  Will exclude any photos that have been marked
        # as deleted.  If you set include_deleted to true, the deleted photos will come back too.
        #
        # This array should not be modified manually.
        def photos(include_deleted = false)
          unless include_deleted
            @photos.select { |photo| !photo.deleted? }
          else
            @photos  
          end
        end
      
        # Attach a photo to the place based on a filename.  Returns the PhotoManager, so you can chain these
        # requests, e.g.
        #
        #   place.photos << 'sample.jpg' << 'test.jpg' << 'third.jpg'
        #  
        def <<(local_path_to_file)
          add(local_path_to_file)
          self
        end

        # Save all the photos.  Each photo knows how to create, update, or delete itself, so this method just
        # cycles through them all and lets them do their thing.
        #
        # Returns true if successful, false otherwise.  Sets the exception method with the exception that was
        # raised when trying to save.
        def save(options = {})
          begin
            save!(options)
            true
          rescue
            @exception = $!
            false
          end
        end

        # Save all the photos.  Each photo knows how to create, update, or delete itself, so this method just
        # cycles through them all and lets them do their thing.
        #
        # Raises an exception if anything fails to save.
        def save!(options = {})
          PublicEarth::Db::Photo.connection.transaction do
            @photos.each do |photo|
              photo.save!(options)
            end
          end
        end
        
        # Save a single photo.
        def save_one(photo, options = {})
          if index = @photos.index(photo)
            saved_photo = nil
            PublicEarth::Db::Photo.connection.transaction do
              saved_photo = @photos.at(index).save!(options)
              @place.photos.record_history(photo)
            end
          end
          saved_photo
        end
        
        def record_history(photo)
          Atlas::History.record(@place, @data_set) do |h|
            h.add_photo(photo)
          end
        end
        
        def logger
          ActiveRecord::Base.logger
        end

      end
    end
  end
end

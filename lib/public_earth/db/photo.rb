require 'public_earth/db/photo_ext/s3_support'
require 'public_earth/db/photo_ext/transmogrifications'
require 'public_earth/db/photo_ext/modification'
require 'public_earth/db/photo_ext/handlers/flickr'
require 'public_earth/db/photo_ext/handlers/url'
require 'public_earth/db/photo_ext/handlers/file'

require 'fileutils'

module PublicEarth
  module Db
    class Photo < PublicEarth::Db::Base
      
      include PublicEarth::Db::PhotoExt::S3Support
      include PublicEarth::Db::PhotoExt::Transmogrifications
      
      module StoredProcedures
        
        def self.create(place_id, source_id, filename, s3_bucket = nil, s3_key = nil, width = nil, height = nil, 
            size_in_kb = nil, caption = nil, copyright = nil, attribution = nil, latitude = nil, longitude = nil,
            created_at = nil)
          PublicEarth::Db::Photo.one.create(place_id, source_id, filename, s3_bucket, s3_key, width, height, 
              size_in_kb, caption, copyright, attribution, latitude, longitude, created_at)
        end
        
        def self.update(id, filename, s3_bucket = nil, s3_key = nil, width = nil, height = nil, size_in_kb = nil,
            caption = nil, copyright = nil, attribution = nil, latitude = nil, longitude = nil)
          PublicEarth::Db::Photo.one.update(id, filename, s3_bucket, s3_key, width, height, size_in_kb, caption, 
              copyright, attribution, latitude, longitude)
        end
        				
        def self.delete(id)
          PublicEarth::Db::Photo.one.delete(id)
        end

      end
      
      class << self
        
        def find_modifications_by_id(id)
          many.modifications(id)
        end
        
        def working_directory=(value)
          FileUtils.mkdir_p(value) unless value.nil?
          @working_directory = value
        end
        
        # Return the current working directory for image files.  Defaults to RAILS_ROOT/tmp/photos.
        def working_directory
          self.working_directory = "#{RAILS_ROOT}/tmp/photos" unless @working_directory
          @working_directory
        end
        
        # Create a new photo in the database.  
        def create(attributes)
          photo = new(attributes)
          photo.save!
        end
        
      end # class self

      # If a local_path_to_file is indicated, pull in the EXIF information to width, height, size, latitude,
      # longitude, etc.
      def initialize(attributes = {})
        super
        calculate_attributes
      end

      # Slice up the full path to the given file into :path, :root (before the .) and extension (after the .).
      # Returns these values in a hash.
      def file_parts
        file = File.split(@attributes[:local_path_to_file])
        path = file[0]
        filename = "#{Time.new.utc.to_i}_#{file[1]}"
        root = filename.sub(/\..*$/,'')
        extension = File.extname(filename).sub(/^\./,'')
        { :path => path, :filename => filename, :root => root, :extension => extension }
      end
      
      # Is there a local file associated with this photo?  Typically true in new files, false in ones that
      # have been retrieved from the database.  The local file must be defined and exist on disk.
      def local?
        @attributes.has_key?(:local_path_to_file) && File.exist?(@attributes[:local_path_to_file])
      end
      
      # Return the base filename associated with the image.  If it has not been manually set, calculates
      # it based on local_path_to_file, should that value exist.
      def filename
        @attributes[:filename] ||= file_parts[:filename]
      end
      
      def local_path_to_file
        @attributes[:local_path_to_file]
      end
      
      def s3_key_for_modification(name)
        m = modification(name)
        m.present? && m.s3_key || nil
      end
      
      # Resets the s3_key and all the calculated attributes, including created_at, latitude, and longitude,
      # in expectation the file has changed. 
      def local_path_to_file=(value)
        @attributes[:local_path_to_file] = value
        reset_attributes
        calculate_attributes
        regenerate_modifications
        value
      end
      
      def external_api_handlers
        # list all of the available third-party photo API modules here (see flickr.rb as example)
        %w{ Flickr Url File }.collect { |handler| PublicEarth::Db::PhotoExt::Handlers.const_get("#{handler}").new }
      end
      
      def generate_url_from_handler
        url = external_api_handlers.each do |handler|
          handler.photo = self
          if handler.can_handle_photo
            break handler.original_photo_url
          end
        end
        url.kind_of?(String) ? url : nil
      end
      
      def set_photo_attributes_from_handler
        external_api_handlers.each do |handler|
          handler.photo = self
          if handler.can_handle_photo
            @attributes[:caption] = handler.get_formatted_caption
            @attributes[:copyright] = handler.get_formatted_copyright
            break
          end
        end
      end
      
      # Return the URL of the photo, on the CDN.  Requires the CLOUDFRONT_SERVER mappings be configured
      # to convert the bundles to CloudFront URLs, otherwise uses the Amazon S3 URL for the bucket.
      #
      # If the photo filename starts with http://, the system assumes it's a remote photo and just 
      # returns the filename.
      def url
        generate_url_from_handler
        # if filename =~ /^http:\/\//          
        #   self.modifications.present? && filename || generate_url_from_handler
        # elsif $cloudfront && $cloudfront[s3_bucket]
        #   "#{$cloudfront[s3_bucket]}/#{s3_key}"
        # else
        #   "http://#{s3_bucket}.s3.amazonaws.com/#{s3_key}"
        # end
      end
      
      # Downloads a copy of the original file.  If the photo has an s3_key, downloads the original from
      # s3.  Otherwise, if the filename starts with http://, copies the file from its remote source.
      #
      # This will overwrite local_path_to_file if present.
      def download_original
        temp_path_to_file = "#{PublicEarth::Db::Photo.working_directory}/#{filename.gsub(/[^\w\.]/, '_')}"
        
        # Download the file...
        parsed = URI.parse(self.url)
        
        response = Net::HTTP.start(parsed.host, parsed.port) do |http|
          http.get(parsed.path)
        end

        raise "Failed to read file; response = #{response.body}" unless response.code == "200"

        # Save the file...
        File.open(temp_path_to_file, 'w') do |file|
          file.write response.body 
        end

        # We set it down here in case the download fails, the local path doesn't accidentally get set.
        self.local_path_to_file = temp_path_to_file
      rescue
        # Invalid URL...just skip it...
        logger.error("ERROR DURING DOWNLOAD ORIGINAL: #{$!}")
        @exception = $!
      end
      
      # We only support JPEG, GIF, PNG
      def valid_file?
        raise "Invalid file format; only JPEG, GIF, and PNG files are supported." unless image_type(local_path_to_file) =~ /jpg|gif|png/
        true
      end
      
      def image_type(file)
        case IO.read(file, 10)
          when /^GIF8/: 'gif'
          when /^\x89PNG/: 'png'
          when /^\xff\xd8/: 'jpg'
        else 'unknown'
        end
      end

      # Convert the array of Rationals and orientation returned from the EXIF JPEG information into a decimal
      # degree value.
      def exif_geo_to_decimal(geo_array, orientation)
        unless geo_array.blank?
          (geo_array[0].to_f + geo_array[1].to_f / 60.0 + geo_array[2].to_f / 3600.0) * (['s', 'S', 'w', 'W'].include?(orientation) && -1 || 1) 
        end
      end

      def source
        query_for :source do
          PublicEarth::Db::Source.find_by_id(self[:source_id])
        end
      end
      
      # Compute the width, height, size (in KB), when the photo was created (created_at), latitude, and 
      # longitude of the photo, based on RMAGICK's read of the file.
      #
      # Will forcibly overwrite width, height, and size, preferring the file details over user-indicated
      # information.  However the created_at, latitude and longitude will be left alone if manually 
      # indicated. 
      #
      # If there is no local_path_to_file defined, calling this method does nothing.
      #
      def calculate_attributes
        if local?
          valid_file?
          file = Magick::Image.read(local_path_to_file).first
          
          if file.format =~ /JPEG/
            exif = EXIFR::JPEG.new(local_path_to_file)
            exif_hash = exif.to_hash
            @attributes[:latitude] ||= exif_geo_to_decimal(exif_hash[:gps_latitude], exif_hash[:gps_latitude_ref])
            @attributes[:longitude] ||= exif_geo_to_decimal(exif_hash[:gps_longitude], exif_hash[:gps_longitude_ref])
          end
          
          @attributes[:width] = file.columns
          @attributes[:height] = file.rows
          @attributes[:size_in_kb] = File.stat(local_path_to_file).size / 1024
          @attributes[:created_at] ||= file.properties['create-date']
          @attributes[:filename] = file_parts[:filename]
        end
      end

      # Reset all the attributes related to the physical metadata surrounding the photo, including
      # width, height, size, creation date, latitude, and longitude.  
      def reset_attributes
        @attributes.delete :width
        @attributes.delete :height
        @attributes.delete :size_in_kb
        @attributes.delete :created_at
        @attributes.delete :latitude
        @attributes.delete :longitude
      end
      
      # Updates the information in this photo object from information in another Photo model.  Does not
      # modify place ID or source ID.
      def update_from(other)
        self.local_path_to_file = other.local_path_to_file if other.local_path_to_file
        self.filename = other.filename
        self.s3_bucket = other.s3_bucket
        self.s3_key = other.s3_key
        if self.method_defined? :width
          self.width = other.method_defined?(:width) ? other.width : self.width
        end
        if self.method_defined? :height
          self.height = other.method_defined?(:height) ? other.height : self.height
        end
        if self.method_defined? :size_in_kb
          self.size_in_kb = other.method_defined?(:size_in_kb) ? other.size_in_kb : self.size_in_kb
        end
        self.caption = other[:caption]
        self.copyright = other[:copyright]
        self.attribution = other[:attribution]
        self.latitude = other[:latitude]
        self.longitude = other[:longitude]
        self.created_at = other[:created_at]
        self
      end
      
      # Raises an exception if the photo can't be saved.  Handles the three cases of creating,
      # updating, and deleting a photo, based on its state.
      def save!(options = {})
        what_to do |state|
          PublicEarth::Db::Photo.connection.transaction do
            case state
            when :create              
              set_photo_attributes_from_handler
              results = StoredProcedures.create(
                  @attributes[:place_id],
                  @attributes[:source_id],
                  @attributes[:filename],
                  @attributes[:s3_bucket],
                  @attributes[:s3_key],
                  @attributes[:width],
                  @attributes[:height],
                  @attributes[:size_in_kb],
                  @attributes[:caption],
                  @attributes[:copyright],
                  @attributes[:attribution],
                  @attributes[:latitude],
                  @attributes[:longitude],
                  @attributes[:created_at]
                )
              self.id = results['id']

              generate_default_transmogrifications
              save_modifications!(options)
              upload_to_s3 unless options[:skip_s3] == true
            
            when :update
              set_photo_attributes_from_handler
              StoredProcedures.update(
                  self.id, 
                  @attributes[:filename],
                  @attributes[:s3_bucket],
                  @attributes[:s3_key],
                  @attributes[:width],
                  @attributes[:height],
                  @attributes[:size_in_kb],
                  @attributes[:caption],
                  @attributes[:copyright],
                  @attributes[:attribution],
                  @attributes[:latitude],
                  @attributes[:longitude]
                )

              save_modifications!(options)
              upload_to_s3 unless options[:skip_s3] == true
            
            when :delete
              clear_modifications!(options)
              StoredProcedures.delete(self.id)
            end
          end
        end
        
        self
      end
      
      # Returns true if the save was successful, false if not.
      def save(options = {})
        trap_exception { save!(options) }
      end
      
      # Shortcut to delete a photo.  Simply sets the deleted flag and calls save.  Raises an exception if
      # the save fails.
      def delete!
        deleted
        save!
      end
      
      # Shortcut to delete a photo.  Simply sets the deleted flag and calls save.  Returns false if the
      # save failed, true if it succeeded.
      def delete
        deleted
        save
      end
      
      # Tests the place_id, source_id and filename for equality.
      def ==(other)
        other.present? &&
        @attributes[:place_id] == other[:place_id] && 
        @attributes[:source_id] == other[:source_id] && 
        @attributes[:filename] == other[:filename]
      end
      
      def user
        query_for :user do
          PublicEarth::Db::Source.find_by_id(source_id).user
        end
      end
      
      def to_hash
        photo_hash = {
          :id => self.id,
          :place => (self.respond_to?:place_id) ?self.place_id : "Place Not Defined",
          :source => (self.source.respond_to?:to_hash) ?self.source.to_hash : "Source Not Defined",
          :filename => self.filename,
          :url => self.url,
          :width => self[:width],
          :height => self[:height],
          :size_in_kb => self[:size_in_kb],
          :caption => self[:caption],
          :copyright => self[:copyright],
          :attribution => self[:attribution],
          :created_at => self[:created_at] && Time.parse(self[:created_at]).xmlschema,
          :updated_at => self[:updated_at] && Time.parse(self[:updated_at]).xmlschema,
          :latitude => self[:latitude],
          :longitude => self[:longitude]
        }

        photo_hash[:transmogrifications] = modifications.map { |m| m.to_hash } if @modifications

        photo_hash
      end
      
      def to_json(*a)
        to_hash.to_json(*a)
      end
      alias :as_json :to_json
      
      def to_plist
        to_hash.to_plist
      end
      
      def to_xml
        xml = XML::Node.new('photo')
        xml['id'] = self.id
        
        xml << xml_value(:place, self.place_id)
        xml << self.source.to_xml
        xml << xml_value(:filename, self.filename)
        xml << xml_value(:url, self.url)
        xml << xml_value(:width, self[:width]) if self[:width]
        xml << xml_value(:height, self[:height]) if self[:height]
        xml << xml_value(:size_in_kb, self[:size_in_kb]) if self[:size_in_kb]
        xml << xml_value(:caption, self[:caption]) if self[:caption]
        xml << xml_value(:copyright, self[:copyright]) if self[:copyright]
        xml << xml_value(:attribution, self[:attribution]) if self[:attribution]
        xml << xml_value(:latitude, self[:latitude]) if self[:latitude]
        xml << xml_value(:longitude, self[:longitude]) if self[:longitude]

        xml << xml_value(:created_at, Time.parse(self[:created_at]).xmlschema) if self[:created_at]
        xml << xml_value(:updated_at, Time.parse(self[:updated_at]).xmlschema) if self[:updated_at]
        
        if @modifications
          modifications_xml = XML::Node.new('transmogrifications')
          modifications.each do |modification|
            modifications_xml << modification.to_xml
          end
          xml << modifications_xml
        end
        
        xml
      end
      
    end
  end
end

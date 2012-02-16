require 'uuidtools'
require 'ostruct'
require 'fileutils'

module PublicEarth
  module Db
    class User < PublicEarth::Db::Base
      include Helper::BoundingBox
      
      attr_accessor :ip_address
      
      # Generate find_by methods for looking up a single record
      finder :email, :username, :username_or_email
      
      class << self
      
        # Since "user" is a tricky reference in databases, we'll use "account" as the schema name.
        def schema_name
          'account'
        end
      
        # Look up a user by his or her unique id.  Return nil if the user does not exist.
        def find_by_id(id)
          results = one.find_by_id_ne(id)
          results && !results['id'].blank? && new(results) || nil
        end

        # Has this account be confirmed, i.e. token-via-email?
        def active?(id)
          existing = find_by_id(id)
          existing && existing.token.nil?
        end
      
        # Authenticate a user using his or her email address and password.  If the authenciation
        # fails for some reason, returns a record with errors set, similar to an ActiveRecord
        # model.  
        #
        # Encrypts the password for you.  
        def authenticate(username_or_email, password)
          user = PublicEarth::Db::User.new
          if username_or_email.blank?
            user.errors.add_to_base("NO_USERNAME")
          elsif password.blank?
            user.errors.add_to_base("NO_PASSWORD")
          else
            existing = find_by_username_or_email(username_or_email)
            if existing
              if active?(existing.id)
                begin
                  user.attributes = one.authenticate(username_or_email, password)
                  user.authenticated = true
                rescue
                  user.errors.add(:username, "INVALID_PASSWORD")
                end
              else
                user.errors.add_to_base("UNCONFIRMED")
              end
            else
              user.errors.add_to_base("INVALID_ACCOUNT")
            end
          end
          user
        end

        # Register a new user with the system.
        def register(attributes = {})
          user = PublicEarth::Db::User.new(attributes)
          
          if attributes[:username].blank?
            user.errors.add(:username, "A username is required.")   
          elsif attributes[:username] =~ /[^\w\-\_\!\@\$\?]/
            user.errors.add(:username, "A username may only contain letters, numbers or the following characters: -_!@$?")   
          elsif PublicEarth::Db::User.find_by_username(attributes[:username])
            user.errors.add(:username, "The username #{attributes[:username]} is already taken.")        
          end
          
          if attributes[:email].blank?
            user.errors.add(:email, "An email address is required.")        
          elsif PublicEarth::Db::User.find_by_email(attributes[:email])
            user.errors.add(:email, "The email address #{attributes[:email]} is already taken.")        
          end

          if attributes[:email] !~ /^[a-zA-Z0-9._%+-]+@(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,4}$/ 
            user.errors.add(:email, "A valid email address is required (eg, myname@somedomain.com).")
          end
 
          if attributes[:password].blank?
            user.errors.add(:password, "A password is required.")        
          elsif attributes[:password] != attributes[:password_confirmation]
            user.errors.add(:password, "The password and its confirmation don't match.")
          end

          if user.errors.empty?
            begin
              user.attributes = one.create(attributes[:username], attributes[:email], attributes[:password], generate_token)
            rescue
              logger.error("Failed to create user account for #{attributes.inspect}:  #{$!}")
              user.errors.add_to_base("Unable to create a user account for #{attributes[:username]}.")
            end
          end

          user
        end
      
        # The preferred way to create a new user is to use the register() method, but this is here
        # for testing and loading data, to create users outside the registration process.  No 
        # registration token is generated by this method!
        def create(attributes)
          new(one.create(attributes[:username], attributes[:email], attributes[:password], attributes[:openid_url], 
              attributes[:first_name], attributes[:last_name], nil))
        end
      
        # After a user registers, he or she must confirm the email address by submitting a token sent
        # to said email.  
        def confirm_new_user(token)
          user = PublicEarth::Db::User.new
          begin
            user.attributes = one.confirm_new_user(token)
          rescue
            # Check with the PostgreSQL exception message to see what kind of error we generated.
            if $! =~ /invalid user/i
              user.errors.add(:email, "An account for #{email} does not exist.")
            else
              user.errors.add_to_base("The given token does not match the one on record.")
            end
          end
          user
        end

        # Generate a temporary token the user may use to login and change his or her password.  The token
        # will be in the user's "forgot_password_token" attribute.
        def forgot_password(email)
          user = PublicEarth::Db::User.new :email => email
          
          if email.blank?
            user.errors.add(:email, "You must specify a valid email address.")
          end
          
          if user.errors.empty?
            begin
              user.attributes = one.forgot_password(email, generate_token)
            rescue
              user.errors.add(:email, "Unable to locate an account for #{email}.")
            end
          end
          user
        end
      
        def authenticate_with_password_token(token)
          user = PublicEarth::Db::User.new
          begin
            user.attributes = one.authenticate_with_password_token(token)
          rescue
            user.errors.add(:token, "Unable to locate an account with token #{token}." )
          end
          
          user
        end

      end # class << self

      # Override and load the user settings information into the Settings object.
      def initialize(attributes = {})
        super(attributes)
      end
      
      def settings
        unless @attributes[:settings].kind_of?(Settings)
          # Gracefully handle corrupted user settings (this happens more often that you'd think)
          begin
            @attributes[:settings] = Settings.new(id, eval(@attributes[:settings] || ''))
          rescue SyntaxError
            @attributes[:settings] = Settings.new(id)
          end
        end
        @attributes[:settings]
      rescue NoMethodError
        raise InvalidUser, "Cannot access settings until User has been hydrated."
      end
      
      def places
        Atlas::User.find(self.id).places
      end

      def saved_places
        Atlas::User.find(self.id).saved_places
      end
      
      # Pre-confirmation email address update
      # this will not actually change the users email address, just
      # create an entry in the users settings. Once confirmed (change_email())
      # it will be updated in the DB.
      def new_email(new_email)
        self.errors.clear
        
        if PublicEarth::Db::User.one.find_by_email_ne(new_email)
          self.errors.add(:email, "The specified email address is not available.")
        end
        
        if self.errors.empty?
          settings.temp_email = new_email
          settings.save

          self.attributes = PublicEarth::Db::User.one.new_email(self.id, PublicEarth::Db::Base::generate_token)
        end

        self
      end
      
      # Change the user's email address
      def change_email(new_email)
        self.errors.clear
        
        if PublicEarth::Db::User.one.find_by_email_ne(new_email)
          self.errors.add(:email, "The specified email address is not available.")
        end
        
        if self.errors.empty?
          self.attributes = PublicEarth::Db::User.one.update_email(self.id, new_email) 
        end
        
        self
      end
    
      # Change this user's password.
      def change_password(new_password, confirm_new_password)
        if new_password.empty?
          self.errors.add(:password, "The password may not be empty.")
        elsif new_password == confirm_new_password
          self.attributes = PublicEarth::Db::User.one.update_password(self.id, new_password, confirm_new_password)
        else
          self.errors.add(:password, "The passwords don't match.")
        end
        
        self
      end
      
      %w(username email password password_confirmation).each do |attr_name|
        define_method("#{attr_name.to_s}=") do |attr_val|
         @attributes[attr_name.to_sym] = attr_val
        end
        
        define_method("#{attr_name.to_s}") do ||
         @attributes[attr_name.to_sym]
        end
      end

      # Handle user settings, which are stored as a TEXT in the user table, settings.  This class allows
      # you to add and remove values in an object-like manner, the results of which are encoded to the
      # standard Ruby binary format and saved in the TEXT.  This class also handles retrieving the
      # settings from the TEXT.
      class Settings < OpenStruct
        def initialize(id, settings = nil)
          super(settings)
          @id = id
        end

        def save
          PublicEarth::Db::User.one.update_settings(@id, self.marshal_dump.inspect.to_s)
        end
      end
    
      # Return a users avatar location
      def avatar
        config = Rails::Configuration.new

        Dir.glob(config.root_path + '/public/assets/users/user_' + self.id.to_s + '*').each do |entry|
          return '/assets/users/' + File.basename(entry)
        end

        '/images/users/user_default.png'
      end

      def avatar=(file)
        config = Rails::Configuration.new
        FileUtils.mkdir_p(config.root_path + '/public/assets/users')

        Dir.glob(config.root_path + '/public/assets/users/user_' + self.id.to_s + '\.*').each do |entry|
          File.delete(entry)
        end

        extension = File.extname(file.filename).blank? ? '' : ".#{File.extname(file.filename)}"
        file.write "#{config.root_path}/public/assets/users/user_#{self.id.to_s}#{extension}"
        File.basename(file.filename)
      end

      # Return a users detailed history
      def history
        @history ||= PublicEarth::Db::History.many.descriptive_changes_by_user(self.id)
      end

      # Return a users rated places
      def rated_places
        @rated_places ||= PublicEarth::Db::User.many.rated_places(self.email) do |place|
          PublicEarth::Db::Place.new(place)
        end
      end

      # Return the user's username name
      def display_name
        #self.email.split('@')[0]
        self.username
      end
    
      # Return the list of all the places this user has created.
      def places_created
        @places_created ||= PublicEarth::Db::Place.created_by_user(self.id, self.source.id)
      end
      alias :created_places :places_created

      # Return the list of all the places this user has modified (but not created).
      def places_modified
        @places_modified ||= PublicEarth::Db::Place.modified_by_user(self.id, self.source.id)
      end
      alias :modified_places :places_modified
      alias :edited_places :places_modified
      alias :places_edited :places_modified
      
      # Return the source record for this user.
      def source
        @source ||= PublicEarth::Db::Source.for_user(self)
      end
      
      # Return the source data set for this user.
      def source_data_set
        @data_set ||= PublicEarth::Db::DataSet.for_user(self)
      end
      alias :data_set :source_data_set
    
      # Generate a unique code for the user to email photos to.  The subject of the email will
      # indicate the name of the place, and the body of the email will be used for descriptions.
      # Geocoding information is taken from the photo's EXIF information.  If any of these pieces
      # are missing, an error message will be emailed back to the user.  Multiple photos will be
      # grouped together into a single place, the area being the bounding box that encompasses 
      # all the photos.
      def generate_photo_email_code
        self.photo_email_code = PublicEarth::Db::User.one.generate_photo_email_code(self.id)['photo_email_code'];
      end
    
      # Saves the last view of the map to the user's database options.  Expects the view to be
      # a hash in the following format.
      #
      #   map_view = {
      #     :center => { :latitude => ..., :longitude => ... },
      #     :zoom => ...,
      #     :bounding_box => { :ne => { ... }, :sw => { ... } }
      #   }
      #
      # The given hash will be merged with any existing map information, so clear or reset any 
      # values you want overwritten.
      def remember_map_view(map_view)
        existing = settings.map_view || {}
        settings.map_view = existing.merge(map_view)
        settings.save
      end
      
      # What was the last map information the user looked at on the map view?  
      def recall_map_view
        settings.map_view
      end
            
      def clear_map_view
        settings.map_view = nil
        settings.save
      end
      
      # Returns true if the user has authenticated.
      def logged_in?
        self.errors.empty?
      end

      def collections
        PublicEarth::Db::Collection.find_by_user(self.id)
      end
      
      def recommended_places(location)
        places = {}

        suggested_moody_categories = []
        ActiveRecord::Base.connection.uncached do
          suggested_moody_categories = PublicEarth::Db::User.many.suggested_moody_categories(self.id).map {|h| OpenStruct.new(h) }
        end
        
        # Of the top 10 preferences, select, at random, 3 of them
        suggested_moody_categories.slice(1,10).sort_by {rand}.slice(1,2).each do |moody_category|
        
          #mood = Atlas::Mood.find_by_id(moody_category.mood_id)
          category = Atlas::Category.find(moody_category.category_id)
          
          # Disabling moods for now since its too constraining when used as a DB query
          # if mood.present?
          #   results = Atlas::Place.bounded(location.bounds).with_photos.categorized(category).feeling_like(mood).find(:all, :limit => 4)
          #   
          #   # Find places that were, in part, responsible for the places we're suggesting
          #   causes = Atlas::Place.find(:all,              
          #                     :select => 'DISTINCT places.*',
          #                     :joins => 'JOIN user_actions ua on ua.place_id = places.id JOIN place_moods pm on pm.place_id = places.id',
          #                     :conditions => ['category_id=? and ua.user_id=? and pm.mood_id=?', category.id, self.id, mood.id],
          #                     :limit => 3)
          #                     
          #   places[mood.name + ' ' + category.name.titleize.pluralize] = {:places => results, :causes => (causes || [])} unless results.empty?
          # 
          # else # no mood present, just category       
          
            # If search ever gets faster, this is a reasonable alternative to the db query
            # collection = PublicEarth::Db::Collection.new :name => 'Suggestions in ' + category.name
            # collection.add_category(category)
            # collection.what.limit = 4
            # 
            # results = collection.places({:where => {:latitude => location.latitude, :longitude => location.longitude, :include => false }})
            
            # Find places that were, in part, responsible for the places we're suggesting
            causes = Atlas::Place.find(:all, 
                              :select => 'DISTINCT places.*',
                              :joins => 'JOIN user_actions ua on ua.place_id = places.id',
                              :conditions => ['category_id=? and ua.user_id=?', category.id, self.id],
                              :limit => 3)

            results = []

            
            # Look for places in bounds with photos in category
            results += Atlas::Place.bounded(location.bounds).with_photos.categorized(category).not_in(causes).find(:all, :limit => 4)
            
            # Failing that, look for places in bounds in category that may *not* have a photo but have been edited (ever)
            if results.length < 4
              results += Atlas::Place.bounded(location.bounds).edited.categorized(category).not_in(causes + results).find(:all, :limit => 4 - results.length)
            end
            
            # Failing that, just get places in bounds in category
            if results.length < 4
              results += Atlas::Place.bounded(location.bounds).categorized(category).not_in(causes + results).find(:all, :limit => 4 - results.length)
            end
            
            # If we have ZERO results, things are looking bleak for the bounds
            # if results.length < 4
            #   if location.parents.present?
            #     logger.debug(">>>>>> Giving up on #{location.label}, searching #{location.parents.first.label} for places in #{category.name}")
            #     parent_location = location.parents.first
            #     results += Atlas::Place.bounded(parent_location.bounds).categorized(category).not_in(causes + results).find(:all, :limit => 4 - results.length)
            #   end
            # end
            
            places[category.name.titleize.pluralize] = {:places => results, :causes => (causes || [])} unless results.length < 2
          # end
        end
        
        places
      end
      
      def to_hash
        {
          :id => self.id,
          :username => self.username,
          :email => self.email,
          :first_name => @attributes[:first_name],
          :last_name => @attributes[:last_name],
          :about => @attributes[:about]
        }
      end
       
      def to_xml
        xml = XML::Node.new('place')
        xml['id'] = self.id

        xml << xml_value(:username, self.username)
        xml << xml_value(:email, self.email)
        xml << xml_value(:first_name, self[:first_name])
        xml << xml_value(:last_name, self[:last_name])
        xml << xml_value(:about, self[:about])

        xml
      end

      def to_json(*a)
        to_hash.to_json(*a)
      end
       
      def to_plist
        to_hash.to_plist
      end
       
      class AuthenticationFailed < StandardError; end
      class InvalidUser < StandardError; end
      class IncorrectPassword < StandardError; end
      class UnconfirmedUser < StandardError; end
    
      class RegistrationFailed < StandardError; end
      class UpdateFailed < StandardError; end
      class UserAlreadyExists < RegistrationFailed; end
      class PasswordMismatch < RegistrationFailed; end
      class EmailMismatch < UpdateFailed; end
      class TokenMismatch < RegistrationFailed; end
    end
  
  end
end


module Atlas
  class User < ActiveRecord::Base
    include PublicEarth::Db::Helper::BoundingBox
    include Atlas::Extensions::Identifiable    
    extend ActiveSupport::Memoizable
    include Atlas::Extensions::User::AuthlogicSupport

    has_one :user_source, :class_name => 'Atlas::UserSource'
    has_one :source, :through => :user_source, :class_name => 'Atlas::Source'
    has_one :facebook_user, :class_name => 'Atlas::FacebookUser', :dependent => :destroy

    has_many :saved_places, :class_name => 'Atlas::SavedPlace', :order => 'created_at desc'
    has_many :places, :through => :saved_places, :class_name => 'Atlas::Place', :order => 'saved_places.created_at desc' do
      def order_by(field, direction)
        order_options = case field
          when 'updated_at': {:table => "saved_places", :field => field, :direction => direction || 'desc'}
          when 'created_at': {:table => "saved_places", :field => field, :direction => direction || 'desc'}
          when 'category_id': {:table => "places", :field => field, :direction => direction || 'asc'}
          when 'nameSort': {:table => "places", :field => 'name', :direction => direction || 'asc'}
          when 'name': {:table => "places", :field => 'name', :direction => direction || 'asc'}
          else {:table => "saved_places", :field => field, :direction => direction || 'desc'}
        end

        find(:all, :order => "#{order_options[:table]}.#{order_options[:field]} #{order_options[:direction]}")
      end
    end

    delegate :ratings, :to => :source

    before_create :generate_token
    after_create :post_create_setup

    serialize :settings

    has_many :placebook_activity, :readonly => true, 
                                  :class_name => 'Atlas::UserAction',
                                  :finder_sql => 'select distinct on (date_part(\'year\', ua.created_at), date_part(\'month\', ua.created_at), date_part(\'day\', ua.created_at), ua.place_id, action) 
                                                  ua.*
                                                  from saved_places sp 
                                                  join places p ON p.id = sp.place_id 
                                                  join user_actions ua ON ua.place_id = p.id
                                                  WHERE sp.user_id = \'#{self.id}\' AND action != \'view\' AND not exists(select 1 from deletions where sp.place_id = deletions.id)
                                                  order by date_part(\'year\', ua.created_at) desc, date_part(\'month\', ua.created_at) desc, date_part(\'day\', ua.created_at) desc, ua.place_id, action, created_at desc
                                                  limit 20'

    has_many :site_activity, :readonly => true,
                             :class_name => 'Atlas::UserAction',
                             :finder_sql => "SELECT DATE_TRUNC('day', user_actions.created_at) as day,
                                               place_id, user_id, action,
                                               MAX(user_actions.created_at) as created_at, count(1)
                                             FROM user_actions
                                             WHERE ((not exists(select 1 from deletions where user_actions.place_id = deletions.id))
                                               AND (user_actions.action <> E'view'
                                               AND user_actions.created_at BETWEEN NOW() - INTERVAL '1 month' AND NOW()))
                                             GROUP BY day, place_id, user_id, action
                                             ORDER BY created_at DESC
                                             LIMIT 20"


    # Returns the source data set for this user.  Always returns the same data set, unless there is a
    # database error and the user has more than one source data set (if so, this violates a business
    # rule).
    #
    # Note that the Atlas::Source also has this method, but it always creates a new source data set.
    # This reflects the business rule:  a user always has a single source data set, while partners get
    # a new set with every data load.
    def source_data_set(options = {})
      if source.source_data_sets.blank?
        source.source_data_sets.create(options.reverse_merge(:name => "Source data set for #{name}"))
      else
        source.source_data_sets.first
      end
    end

    def modified_places
      #Atlas::Place.find_from_search(source.modified_places.find(:all, :select => 'places.id').map(&:id))
      source.modified_places
    end
    
    def created_places
      #Atlas::Place.find_from_search(source.created_places.find(:all, :select => 'places.id').map(&:id))
      source.created_places
    end
  
    def created_or_modified_places
      source.created_or_modified_places
    end
  
    def display_name
      self.username
    end
  
    def self.generate_token
      UUIDTools::UUID.random_create.to_s
    end
    
    def generate_token
      Atlas::User.generate_token
    end
  
    def post_create_setup
      connection.execute("select * from account.post_create_setup('#{id}')")
    end

    def name
      self.username
    end
    
    # So we can mimic the Source class, i.e. @contributing.user is the same if @contributing is either a
    # user or a source.
    def user
      self
    end
    
    def to_s
      self.username
    end
  
    # Converts old user settings (stored as a ruby object dump as String)
    # to new user settings (yaml, slow but convenient)
    def upgrade_settings
      begin      
        self.settings = eval(self.settings) if self.settings.kind_of?(String)
      rescue
        self.settings = {}
      end
      self
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
      save
    end
  
    # What was the last map information the user looked at on the map view?  
    def recall_map_view
      settings.map_view
    end
    
    # Handle user settings, which are stored as a TEXT in the user table, settings.  This class allows
    # you to add and remove values in an object-like manner, the results of which are encoded to the
    # standard Ruby binary format and saved in the TEXT.  This class also handles retrieving the
    # settings from the TEXT.
    class Settings < OpenStruct
      def initialize(user, settings = nil)
        super(settings)
        @user = user
      end

      def save
        @user.settings = self
        @user.save
      end
    end
    
    def settings
      # Gracefully handle corrupted user settings (this happens more often that you'd think)
      begin
        @settings ||= Settings.new(self, eval(read_attribute(:settings) || ''))
      rescue SyntaxError
        @settings ||= Settings.new(self)
      end
      @settings
    end
    
    def settings=(value)
      if value.kind_of?(Settings)
        write_attribute(:settings, value.marshal_dump.inspect.to_s)
      else
        write_attribute(:settings, value)
      end
    end

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
    
    def collections
      PublicEarth::Db::Collection.find_by_user(self.id)
    end    
    
    # Return 'count' random suggestions of gross classifications of places
    # a user very likely will not be interested in at all. (i.e. humor)
    def self.random_suggestions(count)
      Atlas::Category.assignable.find(:all, :order => 'random()', :limit => count)
    end
    
    def to_hash
      {
        :id => self.id,
        :username => self.username,
        # :email => self.email,
        :first_name => self[:first_name],
        :last_name => self[:last_name],
        :about => self[:about]
      }
    end
     
    def to_xml
      xml = XML::Node.new('user')
      xml['id'] = self.id

      xml << xml_value(:username, self.username)
      # xml << xml_value(:email, self.email)
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
    
    def logged_in?
      true
    end
    
    def recommended_places(location)
      places = {}

      suggested_moody_categories = []
      ActiveRecord::Base.connection.uncached do
        suggested_moody_categories = Atlas::User.connection.select_all("select * from account.suggested_moody_categories('#{self.id}')").map {|h| OpenStruct.new(h) }
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
    
    def expertise(limit=nil)
      @expertise ||= returning connection.select_all("select * from account.expertise('#{id}', #{limit || 'null'})").inject(Hash.new {|h,k| h[k] = []}) { |a, n| a[n["key"]] << n["value"]; a } do |expertise|
        expertise['categories'] = expertise['categories'].map {|c| Atlas::Category.find(c)}
      end
    end
    # memoize :expertise
    
    def awards      
      @awards ||= returning connection.select_all("select * from account.activity('#{id}')").inject({}) {|sum, n| sum[n["key"]] = n["value"].to_i; sum } do |awards|
        awards['total_contributions'] = awards['places_created'] + awards['places_edited']
      end 
    end
    # memoize :awards

    def friends(fb_session)
      @friends ||= returning [] do |friends|
        if fb_session.present?
          friends = Atlas::FacebookUser.find_all_by_fb_user_id(fb_session.user.friends_with_this_app.map(&:id)).map(&:user)
        end
      end
    end
    # memoize :friends
  end

end

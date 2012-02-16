module Atlas
  class Place < ActiveRecord::Base    
    extend ActiveSupport::Memoizable
    include Atlas::Extensions::Place::Formats

    include Atlas::Extensions::Identifiable
    
    SRID = 4326     # Latitude/Longitude in decimal degrees, for GeoRuby
    
    class RecordDeleted < ActiveRecord::ActiveRecordError; end
    
    attr_accessor :source_data_set, :content_format, :center_of_collection, :saved_by_user
    attr_accessor :average_rating, :number_of_ratings
    attr_reader :contributing
    
    attr_accessor :history, :rating
    
    validates_presence_of :name
    validates_presence_of :category
    validates_presence_of :contributing
    validates_presence_of :position

    validate :valid_category
    
    before_create :generate_uuid
    before_create :generate_slug
    before_save :update_utm_srid
    
    before_save :update_name, :update_last_modified, :who_moved_it, :validate_category

    after_create :record_create
    
    after_save :insert_place_source_data_set
    after_save :flush_history
    after_save :flush_details
    after_save :update_contributors
    
    include Atlas::Extensions::Place::Search
    
    # Never show deleted places by default
    # default_scope :conditions => 'places.id not in (select id from deletions)'
    default_scope :conditions => 'not exists(select 1 from deletions where places.id = deletions.id)'
    
    def self.find_with_deleted(&block)
      with_exclusive_scope(&block)
    end
     
    # Note, the :conditions option is *ABSOLUTELY* necessary and *MUST NOT* be
    # removed. The condition, which references a column from the second order
    # association table place_values forces rails' AssociationPreload to revert
    # to the pre Rails 2.1 behavior in which a single query is used to load
    # the entire result set of both the place attributes and all their values
    # using a LEFT JOIN. As of Rails 2.1, the strategy changed, and now two
    # queries are used, the second of which is pretty dang slow.
    has_many :place_attributes, :class_name => 'Atlas::PlaceAttribute', 
                                :include => :values, 
                                :conditions => 'place_values.value is null or place_values.value is not null', # DO NOT REMOVE
                                :autosave => true
    
    # TODO:  has_and_belongs_to_many :categories, :class_name => 'Atlas::Category'
    belongs_to :category, :class_name => 'Atlas::Category'
    
    has_many :place_features, :class_name => 'Atlas::PlaceFeature'
    has_many :features, :through => :place_features, :class_name => 'Atlas::Feature'
    
    has_many :place_tags, :class_name => 'Atlas::PlaceTag'
    has_many :tags, :through => :place_tags, :class_name => 'Atlas::Tag'
    
    has_many :ratings, :class_name => 'Atlas::Rating'
    has_many :comments, :class_name => 'Atlas::Comment'
    
    has_many :contributions, :class_name => 'Atlas::Contribution', :autosave => true, :order => 'first_contribution_at ASC'
    has_many :contributors, :through => :contributions, 
        :source => :source, 
        # :conditions => ['contributors.publicly_visible = ? AND (uri is null OR uri NOT LIKE ?)',  true, 'anonymous://%'], 
        :class_name => 'Atlas::Source',
        :order => 'first_contribution_at ASC'
    has_one :creator, :through => :contributions, :source => :source, :conditions => "creator is true", 
        :class_name => 'Atlas::Source'

    has_many :place_source_data_sets, :class_name => 'Atlas::PlaceSourceDataSet'
    has_many :source_data_sets, :through => :place_source_data_sets, :class_name => 'Atlas::SourceDataSet'
      
    has_many :routes, :class_name => 'Atlas::PlaceRoute'
    has_many :regions, :class_name => 'Atlas::PlaceRegion'
    
    has_one :deletion, :class_name => 'Atlas::Deletion', :foreign_key => 'id'
    
    has_many :widget_references, :as => :widget, :class_name => 'Atlas::WidgetReference'
    
    # Expects a standard bounds hash, i.e. { :sw => { :latitude, :longitude }, :ne => { :latitude, :longitude } }
    named_scope :bounded, lambda { |bounds|
      bounds.present? &&
        { 
          :conditions => "position && st_setsrid(st_makebox2d(st_makepoint(#{bounds[:sw][:longitude]}, #{bounds[:sw][:latitude]}), 
            st_makepoint(#{bounds[:ne][:longitude]}, #{bounds[:ne][:latitude]})), #{SRID})" 
        } || {}
      }
    
    # Get the places in the given category or categories.  Handles categories at any level of the hierarchy.
    named_scope :categorized, lambda { |categories|
      categories.present? &&
        {
          :conditions => ["category_id in (select family_member_id from category_family_trees where category_id in (?))", categories]
        } || {}
      }

    # Get the places from the given contributor or contributors.
    named_scope :contributed, lambda { |contributors|
      contributors.present? &&
        {
          :conditions => ["id in (select place_id from contributors where source_id in (?))", contributors]
        } || {}
      }
    
    # Scope is a no-op of user has never rated places
    named_scope :unrated, lambda { |source|
      if source.rated_places.present?
        { :conditions => ["places.id not in (?)", source.rated_places] }
      else
        {}
      end
    }

    named_scope :not_in, lambda {|places|
      if places.present?
        {:conditions => ['places.id not in (?)', places]}
      else 
        {}
      end
    }
    
    named_scope :with_photos, :conditions => "EXISTS(select * from photos where place_id = places.id)"
    
    named_scope :feeling_like, lambda {|mood|      
      {:select => "distinct places.*", :joins => 'join place_moods pm on pm.place_id = places.id', :conditions => {"pm.mood_id" => mood}}
    }
    
    named_scope :edited, :select => 'distinct places.*', 
                         :joins => 'join contributors c on c.place_id = places.id', 
                         :conditions => ['creator = ?', false]


    named_scope :limit, lambda { |limit| { :limit => limit || 10 } }
    named_scope :offset, lambda { |offset| { :offset => offset || 0 } }

    named_scope :saved, :select => 'distinct places.*, sp.created_at as saved_place_created_at',
                        :joins => 'join saved_places sp on sp.place_id = places.id',
                        :order => 'saved_place_created_at DESC'

    named_scope :user_generated, :select => 'distinct places.*', 
                                 :joins => 'join contributors c on c.place_id = places.id join user_sources us on us.source_id = c.source_id',
                                 :conditions => ['creator = ?', true]
    
    # Make sure the category is assignable!                             
    def valid_category
      errors.add(:category_id, "The given category is not assignable.") unless Atlas::Category.assignable.identified(category_id)
    end
    
    def history
      Atlas::History.new(self, contributing)
    end
    memoize :history
    
    def name
      self.details.name
    end
    
    def name=(value)
      raise "Please indicate the place name through details.name."
    end
    
    def latitude
      position.lat    
    end
      
    def latitude=(y)
      self.position = position && position.set_x_y(position.x, y.to_f) || Point.from_x_y(0, y.to_f, SRID)
    end
    
    def longitude
      position.lon
    end
    
    def longitude=(x)
      self.position = position && position.set_x_y(x.to_f, position.y) || Point.from_x_y(x.to_f, 0, SRID)
    end
    
    def lat_long(latitude, longitude)
      if latitude.present? && longitude.present?
        self.position = Point.from_x_y(longitude.to_f, latitude.to_f, SRID)
      end
    end
    
    def route
      routes.first
    end

    def route=(waypoints)
      return if waypoints.blank?
      waypoints = convert_points(waypoints) if waypoints.kind_of? String
      place_route = Atlas::PlaceRoute.new(:source_data_set_id => source_data_set)
      place_route.route = LineString.from_coordinates(waypoints, SRID)
      routes.push(place_route)
    end
    
    def region
      regions.first
    end
    
    def region=(vertexes)
      return if vertexes.blank?
      vertexes = convert_points(vertexes) if vertexes.kind_of? String
      place_region = Atlas::PlaceRegion.new(:source_data_set_id => source_data_set)
      place_region.region = Polygon.from_coordinates([vertexes], SRID)
      regions.push(place_region)
    end
    
    def utm_srid
      current = read_attribute(:utm_srid)
      if current.blank? || current == -1
        update_utm_srid
      else
        current
      end
    end
    
    # Take a string looking like "(lat,long),(lat,long),(lat,long)" into an array of arrays:  [[long,lat],[long,lat],[long,lat]].
    def convert_points(str)
      str.scan(/-?\d+\.?\d*/).map!{ |p| p.to_f }.in_groups_of(2).each { |latlng| latlng.reverse! }
    end
    
    def last_modified
      ((updated_at || created_at) || Time.now).utc
    end
    
    def update_last_modified
      write_attribute :updated_at, Time.now.utc
    end
    
    def who_moved_it
      self.positioned_by_id = @contributing.source.id if changed.include? 'position' 
    end
    
    def record_create # after create
      Atlas::History.record(self, self.contributing) do |h|
        h.created_place(self)
      end
    end
    
    def flush_history # after save
      history.record # write changes to disk
    end

    def flush_details
      self.place_attributes(true)
      @details = nil
    end
    
    def update_utm_srid # before save
      new_utm_srid = ActiveRecord::Base.connection.select_rows("select * from place.convert_to_utm_srid('#{position.as_hex_ewkb}')").flatten.first
      write_attribute(:utm_srid, new_utm_srid)
    end
    
    def to_s
      name.to_s
    end
    
    # Look up the original partner ID for this place for the given source.  If the source is not a 
    # contributor or there is no original ID, returns nil.
    def original_id(source)
      source.present? && Atlas::Place.connection.select_value("select original_id from sources, source_data_sets, place_source_data_sets where
          sources.id = '#{source.id}' and place_source_data_sets.place_id = '#{self.id}' and 
          sources.id = source_data_sets.source_id and source_data_sets.id = place_source_data_sets.source_data_set_id") || nil
    end
    
    # Look up a place by its original ID, from a source.  Source may be either an Atlas::Source object
    # or a source ID.
    def self.find_by_original_id(source, original_id)
      raise "Please indicate a source and original ID" unless source.present? && original_id.present?
      source_id = source.kind_of?(Atlas::Source) && source.id || source
      find :first, :include => [:source_data_sets, :place_source_data_sets],
          :conditions => ["source_data_sets.source_id = ? and place_source_data_sets.original_id = ?",
              source_id, original_id]
    end
    
    # Get the moods associated with this place.  If you pass in a source, returns all the moods 
    # identified by a user.
    def moods(user = nil)
      conditions = user.blank? && ["place_moods.place_id = ?", self.id] || ["place_moods.place_id = ? and place_moods.user_id = ?", self, user.id]
      Atlas::Mood.find(:all, 
          :select => "moods.id, moods.name, count(place_moods.mood_id) as votes",
          :joins => "left join place_moods on place_moods.mood_id = moods.id",
          :conditions => conditions,
          :group => "moods.id, moods.name",
          :order => "votes desc").map { |mood| mood.votes = mood.votes.to_i; mood }
    end
    
    def details
      @details ||= Atlas::Extensions::Place::DetailsManager.new(self)
    end
    
    def details=(value)
      @details = value
    end
    
    # For now, returns PublicEarth::Db::PhotoManager.
    def photos
      @photo_manager ||= PublicEarth::Db::PlaceExt::PhotoManager.new(self)
    end
    alias :photo_manager :photos
    
    # Compute average rating for this place, normalized between -1 and 1
    def average_rating
      @average_rating ||= Atlas::Rating.average(:rating, :conditions => { :place_id => self }).to_f
    end
    
    # Number of times this place has been rated.
    def number_of_ratings
      @number_of_ratings ||= Atlas::Rating.count(:rating, :conditions => { :place_id => self }).to_i
    end
    
    # Contribute new or update existing rating of this place.
    # Rating must be one of 1, 0, or -1.
    # Returns new average rating.
    def rate(rating, source)
      r = Atlas::Rating.find_or_initialize_by_source_id_and_place_id(source, self)
      r.rating = rating
      r.save
      r      
    end
    
    def rating_for_user(source)
      Atlas::Rating.find_by_place_id_and_source_id(self, source)
    end
      
    def self.nearby_recent_unrated_places(location, source, limit, category_id)
      scope = Atlas::Place.bounded(location.bounds)
      
      # This is slow, now its handled below in a condition.
      #scope = scope.unrated(source) if source # no guarantees if user isn't logged in
      
      scope = scope.categorized(category_id) if category_id
      
      if source.present?
        scope.unrated(source).find(:all, :order => 'random(), updated_at DESC', :limit => limit)
      else
        scope.find(:all, :order => 'random(), updated_at DESC', :limit => limit)
      end
    end
    
    def self.nearby_places_with_photos(location, limit, category_id)
      l = location
      
      scope = Atlas::Place.bounded(l.bounds)
      scope = scope.with_photos
      scope = scope.in_category(category_id) if category_id
      
      scope.find(:all, :order => 'random(), updated_at DESC', :limit => limit)
    end
    
    # Who is saving or modifying this place.  Also updates the details model "from" method.
    def contributing=(source_or_user)
      if source_or_user.kind_of? String
        @contributing = Atlas::User.find(:first, :conditions => {:id => source_or_user}) || Atlas::Source.find(source_or_user)
      else
        @contributing = source_or_user
      end
      @source_data_set ||= @contributing.source_data_set
    end
    
    # Insert place source data set *after save*
    def insert_place_source_data_set
      unless self.source_data_sets.include?(@source_data_set)
        self.source_data_sets << @source_data_set
      end
    end
    
    # Generate a unique ID for this object.
    def generate_uuid
      self.id = UUIDTools::UUID.random_create.to_s
    end

    # Pull the name from place details before you save.
    def update_name
      write_attribute(:name, self.details.name.to_s)
    end
    
    # Generate a unique slug for this place, via the database.  Does not save the slug, and does not 
    # guarantee the slug will remain unique!
    def generate_slug
      self.slug = PublicEarth::Db::Place.generate_slug(name, category.id, details.city.to_s, details.country.to_s)
    end

    def update_contributors
      PublicEarth::Db::Contributor.contribute(self.id, @source_data_set.id)
    end
        
    # A very fast way of approximating the total number of places
    # Still kind of Rails'y in that it uses ActiveRecord::Base#count_by_sql
    def self.fast_count
      Atlas::Place.count_by_sql("SELECT reltuples::BIGINT as count FROM pg_class WHERE relkind = 'r' AND relname ='places';")
    end
    
    # This method has been ported from the old PublicEarth::Db::Place for compatibility
    #
    # Look for a set of place IDs and their corresponding categories by slug.  Returns an map of
    # category => place_id.
    def self.find_slug_matches(id_or_slug)
      Hash[*(Atlas::Place.find(:all, :conditions => ["id = ? OR slug = ?",id_or_slug,id_or_slug]).map {|place| [place.category.id, place.id]}).flatten]
    end
    
    # Pass in either a comma-separated string, or an array of objects to assign them as tags to this place.  
    # Old tags will first be stripped away, so include any existing tags you'd like to keep.
    #
    # Setting tags = nil does nothing.  Setting tags to an empty array or empty string will delete all the
    # tags associated with this place.
    def update_tags(tags)
      if tags
        unless tags.kind_of? Array
          tag_names = tags.split(',').map { |tag_name| tag_name.strip.downcase }.compact.uniq.reject { |tag| tag.blank? || !tag.match(/^[a-zA-Z0-9\-\s]*$/) }
        else
          tag_names = tags.map(&:to_s)
        end

        self.tags.clear

        tag_names.each do |tag_name|
          tag = Atlas::Tag.find(:first, :conditions => ["name ~~* ?", tag_name])
          tag = Atlas::Tag.create({:name => tag_name}) if tag.blank?

          Atlas::PlaceTag.create!({:place => self, :tag => tag, :source_data_set => self.contributing.source_data_set})
        end     
        self.reload   
      end
    end
    
    # Make sure this place is assigned to a leaf-level category.  
    #
    # Let me just state once again for the record my objection to this business rule...
    def validate_category
      if Atlas::Category.connection.select_value("select id from category.assignable() where id = '#{self.category_id}'").blank? 
        errors.add(:category, "Invalid category ID '#{self.category_id}':  not a leaf-level category.")
        return false
      end
    end
    
    # Return the list of likely duplcate places for the deduping feature
    def self.matches(name, latitude, longitude, category = nil)
      category_id = category.id if category
      # Want to append the distance and similarity rankings.
      places = find_by_sql ["select * from place.matches(?, #{latitude}, #{longitude}, ?)", name, category]
      matched_places = Hash[*(places.map {|r| [r['id'], r]}).flatten]
      find_from_search(*matched_places.keys).map do |place|
        if place
          place
        end
      end
    end
  
  end
end

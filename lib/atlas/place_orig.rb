module Atlas
  class Place < ActiveRecord::Base
    extend ActiveSupport::Memoizable
  
    named_scope :within_bounds, lambda {|swx, swy, nex, ney| 
      {:conditions => "point_geometry && st_setsrid(st_makebox2d(st_makepoint(#{swx}, #{swy}), st_makepoint(#{nex}, #{ney})), 4326)"}
    }
    
    named_scope :within_location_bounds, lambda {|l| 
      {:conditions => "point_geometry && st_setsrid(st_makebox2d(st_makepoint(#{l.sw_longitude}, #{l.sw_latitude}), st_makepoint(#{l.ne_longitude}, #{l.ne_latitude})), 4326)"}
    }
    
    named_scope :in_category, lambda {|category|
      {:conditions => {:category_id => category}}
    }
    
    named_scope :with_photos, :conditions => "EXISTS(select * from photos where place_id = places.id)"
    
    named_scope :unrated, lambda{|source|
      {
        :select => "places.*", 
        :joins => "left join source_place_ratings r on r.place_id = places.id and source_id='#{source.id}'", 
        :conditions => "rating is null"
      }
    }
    
    named_scope :find_all_by_id_or_slug, lambda{|id_or_slug|
      {:conditions => ["id = ? OR slug = ?", id_or_slug, id_or_slug]}
    }
    
    validates_uniqueness_of :id
    validates_presence_of :name
  
    has_one :place_source_data_set
    has_one :source_data_set, :through => :place_source_data_set
  
    has_many :attribute_values, :class_name => 'Atlas::PlaceAttributeValue'
    has_many :ratings, :class_name => 'Atlas::Rating'
    
    def original_source
      self.source_data_set.source
    end
    memoize :original_source
  
    def details_hash
      self.all_attribute_values.inject({}) {|details, av| details[av.name] = (av.allow_many && [] || av.value ); details }
    end
    memoize :details_hash
    
    def details
      return Details.new(self.all_attribute_values)
    end
    memoize :details
  
    def all_attribute_values
      category_definitions = category.attribute_definitions
    
      attribute_value_def_ids = attribute_values.map(&:attribute_definition_id)
    
      # Remove attributes for which there are already values
      defs_to_initialize = category_definitions.reject {|definition| attribute_value_def_ids.include?(definition.id)}
    
      # Build list of initialized (but not saved) attribute values for these remaining definitions
      empty_attribute_values = defs_to_initialize.map {|definition| Atlas::PlaceAttributeValue.new(:attribute_definition => definition)}
    
      return empty_attribute_values + attribute_values
    end
    memoize :all_attribute_values
  
    has_many :contributions, :class_name => 'Atlas::Contributor'
    has_many :contributing_sources, :through => :contributions, 
                                    :source => :source, 
                                    :conditions => ['contributors.publicly_visible = ? AND (uri is null OR uri NOT LIKE ?)',  true, 'anonymous://%'], 
                                    :uniq => true

    has_one :creator, :through => :contributions, :source => :source, :conditions => "creator is true", :class_name => 'Atlas::Source'
    
    has_many :place_moods, 
             :class_name => 'Atlas::PlaceMood', 
             :group => 'place_id, mood_id', 
             :order => 'count(*)', 
             :select => 'place_id, mood_id',
             :limit => 5
    has_many :moods, :through => :place_moods, :class_name => 'Atlas::Mood'
    
    has_many :place_features, :class_name => 'Atlas::PlaceFeature'
    has_many :features, :through => :place_features, :class_name => 'Atlas::Feature'
    
    has_many :place_tags, :class_name => 'Atlas::PlaceTag'
    has_many :tags, :through => :place_tags, :class_name => 'Atlas::Tag'
    
    belongs_to :category, :class_name => 'Atlas::Category'
    has_many :comments, :class_name => 'Atlas::Comment'
    
    # For now, Atlas#photos returns PublicEarth::Db::PhotoManager
    def photos
      PublicEarth::Db::PlaceExt::PhotoManager.new(self)
    end
    alias :photo_manager :photos
    memoize :photos
    
    before_create :generate_uuid
  
    attr_accessor :head, :latitude, :longitude, :description
  
    def name
      self.details.name
    end
    
    def latitude
      point_geometry.lat    
    end
  
    def latitude=(value)
      point_geometry.y = value
    end
  
    def longitude
      point_geometry.lon
    end
  
    def longitude=(value)
      point_geometry.x = value
    end
  
    def sources
      source_data_sets.map(&:source)
    end
  
    # Generate a unique ID for this object.
    def generate_uuid
      self.id = UUIDTools::UUID.random_create.to_s
    end
    
    # Compute average rating for this place, normalized between -1 and 1
    def rating
      Atlas::Rating.average(:rating, :conditions => ['place_id=?', self.id]).to_f
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
      l = location
      
      scope = Atlas::Place.within_bounds(l.sw_longitude, l.sw_latitude, l.ne_longitude, l.ne_latitude)
      scope = scope.unrated(source) if source # no guarantees if user isn't logged in
      scope = scope.in_category(category_id) if category_id
      
      scope.find(:all, :order => 'random(), updated_at DESC', :limit => limit)
    end
    
    def self.nearby_places_with_photos(location, limit, category_id)
      l = location
      
      scope = Atlas::Place.within_bounds(l.sw_longitude, l.sw_latitude, l.ne_longitude, l.ne_latitude)
      scope = scope.with_photos
      scope = scope.in_category(category_id) if category_id
      
      scope.find(:all, :order => 'random(), updated_at DESC', :limit => limit)
    end
    # TODO: If this could use the same formats module as PublicEarth::Db::Place, it would be terrific.
    def to_json(*a)
      unless self.route_geometry.blank?
        encoder = PublicEarth::Db::PlaceExt::PolylineEncoder.new
        encoded_route = "#{encoder.dp_encode(self.route_as_json)}" # _force_ this to be a string no matter what.
        encoded_route_levels = encoder.encoded_levels
        encoded_route_zoom_factor = encoder.zoom_factor
        encoded_route_num_zoom_levels = encoder.num_levels
      end 
      
      # If this place is a region, encode it.
      unless self.region_geometry.blank?
        encoder = PublicEarth::Db::PlaceExt::PolylineEncoder.new
        encoded_region = "#{encoder.dp_encode(self.region_as_json)}" # _force_ this to be a string no matter what.
        encoded_region_levels = encoder.encoded_levels
        encoded_region_zoom_factor = encoder.zoom_factor
        encoded_region_num_zoom_levels = encoder.num_levels
      end
      
      place_hash = {
        'id' => self.id,
        'name' => self.name.to_s,
        'created_at' => self.created_at, 
        'updated_at' => self.updated_at,
        'latitude' => self.latitude,
        'longitude' => self.longitude,
        # 'elevation' => @attributes[:elevation],
        'encoded_route' => encoded_route,
        'encoded_route_levels' => encoded_route_levels,
        'encoded_route_num_zoom_levels' => encoded_route_num_zoom_levels,
        'encoded_route_zoom_factor' => encoded_route_zoom_factor,
        'route' => self.route_as_json,
        'route_length' => route_length,
        'encoded_region' => encoded_region,
        'encoded_region_levels' => encoded_region_levels,
        'encoded_region_num_zoom_levels' => encoded_region_num_zoom_levels,
        'encoded_region_zoom_factor' => encoded_region_zoom_factor,
        'region' => self.route_as_json,
        'region_area' => self.region_area,
        'rating' => self.rating || 0.0,
        #     'number_of_ratings' => @attributes[:number_of_ratings] || 0,
        #     'score' => @attributes[:score] || 0,
        'category' => self.category,
        'category_id' => self.category.id,
        'category_name' => self.category.name,
        'center_of_collection' => self[:center_of_collection] || false,
        'keywords' => self.tags.map(&:to_s),
        'created_by' => self.creator.to_s(self)
      }

      place_hash['photos'] = self.photos.map { |ph| ph.to_hash }
      # 
      # place_hash['cost'] = self[:cost] if self[:cost].present?
      # 
      # place_hash['distance_in_meters'] = self[:distance_in_meters] if self[:distance_in_meters]
      # place_hash['similarity'] = self[:name_similarity] if self[:name_similarity]
      
      place_hash['details'] = self.details_hash

      place_hash.to_json
    end

    # This method has been ported from the old PublicEarth::Db::Place for compatibility
    #
    # Look for a set of place IDs and their corresponding categories by slug.  Returns an map of
    # category => place_id.
    def self.find_slug_matches(id_or_slug)
      Hash[*(find_all_by_id_or_slug(id_or_slug).map {|place| [place.category.id, place.id]}).flatten]
      #Hash[*(find_by_slug_or_place_id(slug_or_id).map {|places| [results['category_id'], results['id']]}).flatten]
    end
    
    class Details
      class MultiValuedAttribute
        attr_accessor :values

        def initialize(attribute)
          @attribute = attribute
          @values = attribute.value.present? && [attribute.value] || []
        end
        
        def value
          @values
        end
        # Pass-through to real PlaceAttributeValue
        def method_missing(method, *args)          
          return @attribute.send(method, *args) if @attribute.respond_to?(method)
          raise NoMethodError.new(method.to_s)
        end
        
        include Enumerable        
        def each
          @values.each {|value| yield OpenStruct.new(:value => value, :comments => nil)}
        end
      end
      
      attr_reader :attributes
      def initialize(attributes)
        # Convert attributes array to hash for storage
        @attributes = attributes.inject({}) do |details, av| 
          if details.has_key?(av.name) && av.allow_many
            details[av.name].values << av.value
          else
            if av.allow_many
              details[av.name] = MultiValuedAttribute.new(av)
            else
              details[av.name] = av
            end
          end
          details 
        end
      end
      
      def method_missing(method, *args)
        if method.to_s =~ /^has_.*\?$/
          return @attributes.has_key?(method.to_s)
        end
        
        return @attributes[method.to_s] if @attributes.has_key?(method.to_s)
        raise NoMethodError.new(method.to_s)
      end

      include Enumerable
      
      # Excludes any attributes that have been deleted by default.  If you'd like to include those,
      # pass in true for include_deleted.
      def each
        @attributes.values.each do |attribute|
          yield attribute
        end
      end    
    end
    
  end
  
end

module PublicEarth
  module Db
    class Source < PublicEarth::Db::Base

      finder :name
      finder :uri
      
      class << self
      
        # Caches the source.
        def find_by_id!(id)
          cache_manager.ns(:sources).get_or_cache(id) do 
            new(one.find_by_id(id))
          end
        end

        # Caches the source.
        def find_by_id(id)
          cache_manager.ns(:sources).get_or_cache(id) do 
            construct_if_found one.find_by_id_ne(id)
          end
        end
      
        # Create a new source object.  Name is required; URI is optional.
        def create(attributes)
          attributes = {:name => attributes} if attributes.kind_of?(String)
          new(one.create(attributes[:name], attributes[:uri]))
        end
      
        # Get an existing source, or create it if it doesn't exist.  Requires name; URI is optional.
        def find_or_create(name, uri = nil)
          new(one.find_or_create(name, uri))
        end
        
        # Find the content source for the given user.  If one does not exist for this user, it will be created.
        def for_user(user_id)
          if user_id.kind_of? PublicEarth::Db::User
            user = user_id
            user_id = user.id
          end
          
          cache_manager.ns(:sources_by_user).get_or_cache(user_id) do
            source = new(one.for_user(as_id(user_id)))
            source.user = user || PublicEarth::Db::User.find_by_id!(user_id)
            
            # Let's save the source with the user in it too
            cache_manager.ns(:sources).put(source.id, source)
            
            source
          end
        end
      
        # Return the source that created the given place.
        def creator_of(place_id)
          place_id = place_id.id if place_id.kind_of?(PublicEarth::Db::Place) || place_id.kind_of?(Place)
          new(PublicEarth::Db::Source.one.creator(place_id) || raise("Invalid place ID #{place_id} or the source records are bad."))
        end
        
        # Return the sources that contributed information to the given place.  This will only return valid,
        # authenticated sources, i.e. authenticated users and data partners.  Anonymous, IP address-only
        # sources are ignored.
        #
        # You may indicate whether or not to include only sources that should be visible to users of the
        # PublicEarth site. 
        def contributed_to(place_id, visible_only = false)
          many.contributed_to(place_id, visible_only).map { |result| new(result) }
        end
        
      end # class << self
    
      # Source is very picky about what attributes it will accept.  It doesn't do the generic attribute
      # loading, so that it can bring in source and user information simultaneously with a single call.
      def initialize(attributes = {})
        @attributes = {}
        
        if attributes
          attributes = Hash[*(attributes.map {|key, value| [key.to_sym, value]}).flatten]
          @attributes.merge! :id => attributes[:id], :name => attributes[:name], :uri => attributes[:uri],
              :created_at => attributes[:created_at] && Time.parse(attributes[:created_at]) || nil, 
              :updated_at => attributes[:updated_at] && Time.parse(attributes[:updated_at]) || nil,
              :icon_path => attributes[:icon_path], :publicly_visible => attributes[:publicly_visible],
              :copyright => attributes[:copyright], :icon_only => (attributes[:icon_only] == true || attributes[:icon_only] == 't')
            
          if attributes[:user_id]
            self.user = PublicEarth::Db::User.new :id => attributes[:user_id], :email => attributes[:email],
                :first_name => attributes[:first_name], :last_name => attributes[:last_name], 
                :created_at => attributes[:user_created_at] && Time.parse(attributes[:user_created_at]) || nil, 
                :updated_at => attributes[:user_updated_at] && Time.parse(attributes[:user_updated_at]) || nil,
                :settings => attributes[:settings], :about => attributes[:about], :username => attributes[:username]
          end
        else
          nil  
        end
      end
      
      # Is this source record associated with a user account?  This will test if the @user variable has been
      # assigned yet without trying to load it.  If you've retrieve a source by ID or name, it will load in
      # the user information if it's available at the same time, so this method will indicate that the source
      # is for a user or not.  However, calling the user method will try to load the user if the @user 
      # variable hasn't been set, which means a database call every time if there is no user.  
      def user?
        !! @attributes[:user]
      end
      
      # Is this source an anonymous user?  Tests the URI as anonymous://.  Returns the IP address of the 
      # source.
      def anonymous_user?
        @attributes[:uri] =~ /^anonymous\:\/\/(.*)$/
        $1 || false
      end
      
      # Return the user account associated with this user, if any.
      def user
        query_for :user do
          PublicEarth::Db::User.one.from_source(self.id)
        end
      end

      # This is used internally to set the user from a query with the user information joined to the source.
      # It does not modify the database at all!
      def user=(value)
        assign :user, value
      end
      
      def source_data_set
        @data_set ||= PublicEarth::Db::DataSet.for_source(self.id)
      end
      alias :data_set :source_data_set
      
      # Alias for publicly_visible?  Returns true if the source can be displayed to the public.  This method
      # is only valid in the context of looking at a source through a place, such as the place contributor
      # or creator.  Otherwise, visibility is meaningless and will generate an error.
      def visible?
        self.publicly_visible? == false
      end
      
      # Returns the source name.  
      #
      # * if the source is a user, return that user's username
      # * if the source is an anonymous user, return "Anonymous User"
      # * if the source is a visible source, return the source name
      # * if the source is invisible, return nil
      def to_s
        (user? && user.username) || anonymous_user? || (visible? && self.name) || 'PublicEarth'
      end
      
      def to_hash
        hash = {
          :id => self.id,
          :name => to_s,
          :uri => (visible? ? self.uri : 'http://www.publicearth.com'),
          :copyright => self[:copyright],
          :icon => self[:icon]
        }
        hash[:user] = self.user.to_hash if self.user
        hash
      end
      
      def to_json(*a)
        to_hash.to_json(*a)
      end
      
      def to_xml
        xml = XML::Node.new('source')
        xml['id'] = self.id

        xml << xml_value(:name, to_s)
        xml << xml_value(:uri, (visible? ? self[:uri] : 'http://www.publicearth.com'))
        xml << xml_value(:copyright, self[:copyright])
        xml << xml_value(:icon, self[:icon])
        
        xml << user.to_xml if user
        
        xml
      end
      
      def to_plist
        to_hash.to_plist
      end
      
    end
  end
end

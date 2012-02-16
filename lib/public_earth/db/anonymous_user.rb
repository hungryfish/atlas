require 'uuidtools'

module PublicEarth
  module Db

    # TODO:  Flesh this out
    class AnonymousUser
      include Helper::BoundingBox
      
      attr_reader :ip_address
      attr_accessor :current_session
      
      # Record the current IP address and the current session.  We save bits of information to the 
      # session for the user, since we don't have a database account available.
      def initialize(ip_address, current_user_session)
        @guid = UUIDTools::UUID.random_create.to_s
        @ip_address = ip_address
        @current_session = current_user_session
      end

      def id
        @guid
      end
      
      def avatar
        '/images/users/user_default.png'
      end
      
      # Set the value in the session.
      def set(session_variable, value)
        current_session[session_variable] = value
      end
       
      # Get the stored value for this user.
      def get(session_variable, optional = nil)
        current_session[session_variable] ||= optional
      end
      
      # Has this value been set?
      def has?(session_variable)
        !! get(:session_variable)
      end
      
      # Wipe out any session variables for this user.  Useful when the user logs in.
      def clear
        set :map_view, nil
        set :data_set, nil
      end
      
      # Save the last view of the map to the session.  Expects the view to be
      # a hash in the following format.
      #   map_view = {
      #     :center => { :latitude => ..., :longitude => ... },
      #     :zoom => ...
      #   }
      def remember_map_view(map_view)
        if map_view
          set(:map_view, get(:map_view, {}).merge(map_view))
        else
          set :map_view, nil
        end
      end
      
      # What was the last bounding box the user looked at on the map?  If there isn't one, let's get
      # a GeoIP guess at the map position! 
      def recall_map_view
        get :map_view
      end
      
      # Clear map view only
      def clear_map_view
        set :map_view, nil
      end
      
      # Call this when the user logs in to transfer any information created before the user logged
      # in, such as the last map view bounding box or device queue places.
      def update_authenticated_user(authenticated_user)
        authenticated_user.remember_map_view(recall_map_view) if recall_map_view
        authenticated_user.ip_address = @ip_address
        clear
      end

      def places; []; end
      def collections; []; end
      
      # Return the source data set for this user.
      def source_data_set
        get :data_set, PublicEarth::Db::DataSet.for_anonymous(@ip_address, get(:tracking_id, UUIDTools::UUID.random_create.to_s))
      end
      alias :data_set :source_data_set
      
      def logged_in?
        return false
      end
      alias :authenticated? :logged_in? 
    end
  end
end

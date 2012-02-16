module PublicEarth
  module Db
    module Helper
      
      # Utilties for all types of users to calculate the bounding box to search on the map.
      #
      # TODO:  Refactor for existing bounding box uses! (is this a helper, even?)
      module BoundingBox
        
        US = {
            :sw => { :latitude => 23.885837699862005, :longitude => -130.166015625 },
            :ne => { :latitude => 52.16045455774703, :longitude => -61.611328125 }
          }
        
        BOULDER = { :latitude => 40.0105, :longitude => -105.2768 }

        # Return the bounding box for the current user.  Tries a few things:
        #
        # # From the map_view information (recall_map_view)
        # # By taking the map center and zoom from the map_view and attempting to construct a bounding box
        # # Using the IP address of the user to look up a map center, then calculate a box using the default view
        # # Default to the bounding box around the United States.
        #
        # Bounding box is used primarily for search, so it's o.k. to be inaccurate and guess small.  Presumably
        # it's a "first pass" to load some initial data, then the map will be displayed and the user can 
        # submit the correct bounding box to remember_map_view.
        def bounding_box(ip_address = @ip_address)
          #ip_address = '97.122.182.180'
          map_view = recall_map_view || {}

          # In the session?
          if map_view.include? :bounding_box
            map_view[:bounding_box]

          # Map center?
          elsif map_view.include? :center
            calculate_bounding_box(map_view[:center])

          # GeoIP?
          elsif ip_address
            begin
              location = PublicEarth::GeoIp::Location.get_location(:from => ip_address)
            rescue
              PublicEarth::Db::Helper::BoundingBox::US
            end

          # U.S. (default)
          else 
            PublicEarth::Db::Helper::BoundingBox::US
          end
        end

        # Try to determine a rather close bounding box around the given center.  The "center" may either be
        # a hash, with :latitude and :longitude keys, or it may be an array, with latitude first, or it may
        # be two parameters, latitude and longitude.  We're easy...
        def calculate_bounding_box(*attributes)
          center = attributes.length == 2 && [attributes[0], attributes[1]] || attributes.first
          if center.kind_of?(Array) && center.length == 2
            center.map! { |value| value.to_f }
            {
              :sw => { :latitude => center.first - 0.25, :longitude => center.last - 0.25 },
              :ne => { :latitude => center.first + 0.25, :longitude => center.last + 0.25 }
            }
          elsif center.kind_of?(Hash) && center.include?(:latitude) && center.include?(:longitude)
            {
              :sw => { :latitude => center[:latitude].to_f - 0.25, :longitude => center[:longitude].to_f - 0.25 },
              :ne => { :latitude => center[:latitude].to_f + 0.25, :longitude => center[:longitude].to_f + 0.25 }
            }
          elsif center.nil?
            nil
          else
            raise "Invaild center attribute when trying to calculate bounding box."
          end
        end
        
        # Return the center of the map for the current user.  If we can find a center, default to Boulder.
        def position(ip_address = @ip_address)
          map_view = recall_map_view || {}

          # In the session?
          if map_view.include? :center
            map_view[:center]

          # Calculate from the bounding box?
          elsif map_view.include? :bounding_box
            map_view[:center] = calculate_centroid(map_view[:bounding_box])

          # GeoIP?
          elsif ip_address
            begin
              location = GeoIp::Location.find(ip_address)
              map_view[:center] = { :latitude => location.latitude.to_f, :longitude => location.longitude.to_f }
            rescue
              PublicEarth::Db::Helper::BoundingBox::BOULDER
            end
          # Boulder, CO (default)
          else 
            PublicEarth::Db::Helper::BoundingBox::BOULDER
          end
        end

        # Calculate the center of the bounding box or other area.  
        def calculate_centroid(bounding_box)
          latitude = (bounding_box[:sw][:latitude].to_f + bounding_box[:ne][:latitude].to_f) / 2.0
          longitude = (bounding_box[:sw][:longitude].to_f + bounding_box[:ne][:longitude].to_f) / 2.0
          { :latitude => latitude, :longitude => longitude }
        end

      end
    end
  end
end
        
module PublicEarth
  module Db
    module GeoIp
    
      # A city in the GeoIP space.  This is not currently related to a PublicEarth place directly.
      class Location < PublicEarth::Db::Base
      
        # Look up a location by its IP address.
        def self.find(ip_address)
          begin
            hash = call_for_one('geoip.find_city_from_ip_address', ip_address)
            raise "No Location Found. Boo Urns." if hash.blank?
            PublicEarth::Db::GeoIp::Location.new(hash)
          rescue
            raise InvalidLocationError, "There isn't a location associated with #{ip_address}."
          end
        end
        
        def latitude
          @attributes[:latitude].to_f
        end
        
        def longitude
          @attributes[:longitude].to_f
        end
      end
    
      # The IP address could not be mapped to a place.
      class InvalidLocationError < StandardError; end
    end
  end
end
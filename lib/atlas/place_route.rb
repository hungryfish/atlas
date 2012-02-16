module Atlas
  class PlaceRoute < ActiveRecord::Base
    
    attr_reader :encoded_route, :encoded_route_levels, :encoded_route_zoom_factor, :encoded_route_num_zoom_levels
    
    belongs_to :place, :class_name => 'Atlas::Place'
    
    validate :valid_route
    
    def valid_route
      errors.add(:route, "A route must be a LINESTRING.") unless route.kind_of? LineString
      errors.add(:route, "A route must have more than one point.") unless route.points.length > 1
    end
    
    # Returns the points in this route as an array of latitude, longitude: [[lat, lng], [lat, lng], ...].
    def as_array
      route.points.map {|p| [p.lat, p.lng]}
    end
   
    # Returns the points in this route as JSON-esque string of latitude, longitude: "(lat, lng),(lat, lng)".
    def as_string
      (route.points.map { |p| "(#{p.lat},#{p.lng})" }).join(',')
    end
    
    # Configure the Google Maps encodings for this route.
    def encode(options = {})
      encoder = Atlas::Util::PolylineEncoder.new(options)
      @encoded_route = encoder.dp_encode(as_array).to_s 
      @encoded_route_levels = encoder.encoded_levels
      @encoded_route_zoom_factor = encoder.zoom_factor
      @encoded_route_num_zoom_levels = encoder.num_levels
    end
    
    def to_hash
      encode
      {
        'encoded_route' => self.encoded_route,
        'encoded_route_levels' => self.encoded_route_levels,
        'encoded_route_num_zoom_levels' => self.encoded_route_num_zoom_levels,
        'encoded_route_zoom_factor' => self.encoded_route_zoom_factor,
        'route' => self.as_string,
        'route_length' => self.length_in_meters
      }
    end
    
  end
end

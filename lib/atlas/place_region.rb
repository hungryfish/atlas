module Atlas
  class PlaceRegion < ActiveRecord::Base
    
    attr_accessor :encoded_region, :encoded_region_levels, :encoded_region_zoom_factor, :encoded_region_num_zoom_levels

    belongs_to :place, :class_name => 'Atlas::Place'

    validate :validate_polygon
    validate :validate_only_one_ring
    validate :validate_number_of_points_in_ring
    validate :validate_ring_is_closed
    
    def validate_polygon
      errors.add(:region, "must be a POLYGON.") unless region.kind_of? Polygon
    end
    
    def validate_only_one_ring
      errors.add(:region, "may only be a single ring.") if region.rings.length != 1
    end
    
    def validate_number_of_points_in_ring
      errors.add(:region, "ring must contain three or more points.") if region.rings.first.points.length < 3
    end

    # This method doesn't so much validate, as close the polygon ring if it's open.
    def validate_ring_is_closed
      region.rings.first.points << region.rings.first.points.first unless region.rings.first.is_closed
    end
    
    # Returns the points in this region as an array of latitude, longitude: [[lat, lng], [lat, lng], ...].
    def as_array
      region.rings.first.points.map {|p| [p.lat, p.lng]}
    end
   
    # Returns the points in this region as JSON-esque string of latitude, longitude: "(lat, lng),(lat, lng)".
    def as_string
      (region.rings.first.points.map { |p| "(#{p.lat},#{p.lng})" }).join(',')
    end
    
    # Configure the Google Maps encodings for this region.
    def encode(options = {})
      encoder = Atlas::Util::PolylineEncoder.new
      @encoded_region = encoder.dp_encode(as_array).to_s
      @encoded_region_levels = encoder.encoded_levels
      @encoded_region_zoom_factor = encoder.zoom_factor
      @encoded_region_num_zoom_levels = encoder.num_levels
    end
    
    def to_hash
      encode
      {
        'encoded_region' => self.encoded_region,
        'encoded_region_levels' => self.encoded_region_levels,
        'encoded_region_num_zoom_levels' => self.encoded_region_num_zoom_levels,
        'encoded_region_zoom_factor' => self.encoded_region_zoom_factor,
        'region' => self.as_string,
        'region_area' => self.area_in_sq_meters
      }
    end
    
  end
end
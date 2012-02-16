module PublicEarth
  module Db
    module PlaceExt
      
      # Output formats for the Place models:  JSON, KML, RSS, XML, etc.  
      #
      # TODO:  Not all formats are implemented yet!
      module Formats

        # Generate the GeoRSS XML for a place.  Pass in a reference to a builder for this XML to
        # attach itself to.  If none is supplied, a full GeoRSS XML document will be returned.
        def to_georss(builder = nil)
          # TODO!
        end

        # Render JSON from place.  If details have been loaded, they will be included.
        def to_json(*a)
          place_hash = {
            'id' => self.id,
            'name' => self.name.to_s,
            'created_at' => @attributes[:created_at],
            'updated_at' => @attributes[:updated_at],
            'latitude' => self.latitude,
            'longitude' => self.longitude,
            'elevation' => @attributes[:elevation],
            'encoded_route' => @attributes[:encoded_route],
            'encoded_route_levels' => @attributes[:encoded_route_levels],
            'encoded_route_num_zoom_levels' => @attributes[:encoded_route_num_zoom_levels],
            'encoded_route_zoom_factor' => @attributes[:encoded_route_zoom_factor],
            'route' => @attributes[:route],
            'route_length' => @attributes[:route_length],
            'encoded_region' => @attributes[:encoded_region],
            'encoded_region_levels' => @attributes[:encoded_region_levels],
            'encoded_region_num_zoom_levels' => @attributes[:encoded_region_num_zoom_levels],
            'encoded_region_zoom_factor' => @attributes[:encoded_region_zoom_factor],
            'region' => @attributes[:region],
            'region_area' => @attributes[:region_area],
            'rating' => @attributes[:rating] || 0.0,
            'number_of_ratings' => @attributes[:number_of_ratings] || 0,
            'score' => @attributes[:score] || 0,
            'category' => self.category,
            'category_id' => self.category.id,
            'category_name' => self.category.name,
            'center_of_collection' => self[:center_of_collection] || false,
            'keywords' => self.tags.map(&:to_s),
            'created_by' => self.created_by.to_s
          }

          if @photo_manager
            place_hash['photos'] = self.photos.map { |ph| ph.to_hash }
          end
          
          place_hash['cost'] = self[:cost] if self[:cost].present?

          place_hash['distance_in_meters'] = self[:distance_in_meters] if self[:distance_in_meters]
          place_hash['similarity'] = self[:name_similarity] if self[:name_similarity]
          
          place_hash['details'] = details.to_hash if details?

          place_hash['saved_by_user'] = self[:saved_by_user] if self[:saved_by_user]
          
          place_hash.to_json
        end

        # Returns a Ruby LibXML Node.  If you want to return a single category to an application,
        # you should wrap this in a proper XML Document.
        #
        # === Sample XML Results
        # 
        #   <category id="Accommodations">
        #     <name xml:lang="en">Hotels &amp; Motels</name>
        #     <children>10</children>
        #     <places>275343</places>
        #   </category>
        #
        def to_xml
          xml = XML::Node.new('place')
          xml['id'] = self.id
  
          name = XML::Node.new('name') << as_cdata(self.name)
          name.lang = @attributes[:language] || 'en'
          xml << name
          
          xml << XML::Node.new('created_at', Time.parse(self.created_at).xmlschema) if @attributes[:created_at]
          xml << XML::Node.new('updated_at', Time.parse(self.updated_at).xmlschema) if @attributes[:updated_at]

          xml << XML::Node.new('latitude', self.latitude.to_s)
          xml << XML::Node.new('longitude', self.longitude.to_s)
          xml << XML::Node.new('elevation', @attributes[:elevation]) unless @attributes[:elevation].blank?

          xml << XML::Node.new('route', @attributes[:route]) unless @attributes[:route].blank? 
          xml << XML::Node.new('route_length', @attributes[:route_length].to_s) unless @attributes[:route_length].blank? 
          xml << XML::Node.new('region', @attributes[:region]) unless @attributes[:region].blank? 
          xml << XML::Node.new('region_area', @attributes[:region_area].to_s) unless @attributes[:region_area].blank? 

          xml << XML::Node.new('rating', !@attributes[:rating].blank? && @attributes[:rating].to_s || '0.0') 
          xml << XML::Node.new('number_of_ratings', !@attributes[:number_of_ratings].blank? && @attributes[:number_of_ratings].to_s || '0') 
          xml << XML::Node.new('score', !@attributes[:score].blank? && @attributes[:score].to_s || '0') 
          xml << XML::Node.new('center_of_collection', self[:center_of_collection].to_s || 'false')

          xml << self.category.to_xml
          
          keywords = XML::Node.new('keywords')
          self.tags.each do |tag|
            keywords << xml_value(:keyword, tag)
          end
          xml << keywords
          
          xml << XML::Node.new('created_by') << self.created_by.to_xml
          
          contributors = XML::Node.new('contributors')
          self.contributors.each do |contributor|
            contributors << (XML::Node.new('contributor') << contributor.to_xml)
          end
          xml << contributors
          
          xml << details.to_xml if details?

          xml << xml_value(:distance_in_meters, self[:distance_in_meters]) if self[:distance_in_meters]
          xml << xml_value(:similarity, self[:name_similarity]) if self[:name_similarity]

          xml
        end

        # Returns the Apple plist representation of this category.  Represents a single category
        # object; needs to be wrapped in an XML document and an array or dict.
        def to_plist
          place_hash = {
            'id' => self.id,
            'name' => self.name,
            'created_at' => @attributes[:created_at],
            'updated_at' => @attributes[:updated_at],
            'latitude' => self.latitude,
            'longitude' => self.longitude,
            'elevation' => @attributes[:elevation],
            'route' => @attributes[:route],
            'route_length' => @attributes[:route_length],
            'region' => @attributes[:region],
            'region_area' => @attributes[:region_area],
            'rating' => !@attributes[:rating].blank? && @attributes[:rating] || 0.0,
            'number_of_ratings' => !@attributes[:number_of_ratings].blank? && @attributes[:number_of_ratings] || 0,
            'score' => @attributes[:score] || 0,
            'keywords' => self.tags,
            'center_of_collection' => self[:center_of_collection] || 'false'
          }

          place_hash['distance_in_meters'] = self[:distance_in_meters] if self[:distance_in_meters]
          place_hash['similarity'] = self[:name_similarity] if self[:name_similarity]

          place_hash['category'] = {
            'id' => self.category.id,
            'name' => self.category.name,
          }
          
          place_hash['details'] = details.to_hash(:include_comments => true) if details?
          
          place_hash['created_by'] = self.created_by
          place_hash['contributors'] = self.contributors
          
          place_hash.to_plist
        end
      end
    end
  end
end

module Atlas
  module Extensions
    module Place
      module Formats

        extend ActiveSupport::Memoizable

        def to_hash
          place_hash = {
            'id' => self.id,
            'slug' => self.slug,
            'name' => self.name.to_s,
            'created_at' => self.created_at,
            'updated_at' => self.updated_at,
            'latitude' => self.latitude,
            'longitude' => self.longitude,
            'elevation' => self.elevation_in_meters,
            'average_rating' => self.average_rating,
            'number_of_ratings' => self.number_of_ratings,
            'category' => self.category,
            'keywords' => self.tags.map(&:to_s),
            'created_by' => self.creator && self.creator.to_s(self.id) || Atlas::Source.random_name
          }

          if routes.present?
            place_hash.merge! routes.first.to_hash
          end

          if regions.present?
            place_hash.merge! regions.first.to_hash
          end

          place_hash['details'] = details.to_hash

          if @photo_manager
            place_hash['photos'] = self.photos.map { |ph| ph.to_hash }
          end

          place_hash['distance_in_meters'] = self[:distance_in_meters] if self[:distance_in_meters]
          place_hash['similarity'] = self[:name_similarity] if self[:name_similarity]
          place_hash['saved_by_user'] = self.saved_by_user if self.saved_by_user
          place_hash['center_of_collection'] = self.center_of_collection if self.center_of_collection

          place_hash
        end

        # Render JSON from place.  If details have been loaded, they will be included.
        def to_json(*a)
          hash = nil
          hash = to_hash

          json = nil
          json = hash.to_json

          return json
        end

        alias :as_json :to_json
        memoize :to_json

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
          name.lang = self[:language] || 'en'
          xml << name

          xml << XML::Node.new('created_at', self[:created_at].xmlschema) if self[:created_at].present?
          xml << XML::Node.new('updated_at', self[:updated_at].xmlschema) if self[:updated_at].present?

          xml << XML::Node.new('latitude', self.latitude.to_s)
          xml << XML::Node.new('longitude', self.longitude.to_s)
          xml << XML::Node.new('elevation', self[:elevation]) unless self[:elevation].blank?

          xml << XML::Node.new('route', self[:route]) unless self[:route].blank?
          xml << XML::Node.new('route_length', self[:route_length].to_s) unless self[:route_length].blank?
          xml << XML::Node.new('region', self[:region]) unless self[:region].blank?
          xml << XML::Node.new('region_area', self[:region_area].to_s) unless self[:region_area].blank?

          xml << XML::Node.new('rating', !self[:rating].blank? && self[:rating].to_s || '0.0')
          xml << XML::Node.new('number_of_ratings', !self[:number_of_ratings].blank? && self[:number_of_ratings].to_s || '0')
          xml << XML::Node.new('score', @score.present? && @score.to_s || '0')
          xml << XML::Node.new('center_of_collection', self[:center_of_collection].to_s || 'false')

          xml << self.category.to_xml
          
          xml << self.photos.first.to_xml if self.photos.first

          keywords = XML::Node.new('keywords')
          self.tags.each do |tag|
            keywords << xml_value(:keyword, tag)
          end
          xml << keywords

          if self.creator
            if self.creator.visible_for? self
              xml << XML::Node.new('creator') << self.creator.to_xml
            else
              xml << XML::Node.new('creator')
            end
          end

          contributors = XML::Node.new('contributors')
          self.contributors.each do |contributor|
            contributors << (XML::Node.new('contributor') << contributor.to_xml) if contributor.visible_for? self
          end
          xml << contributors

          xml << details.to_xml

          xml << xml_value(:distance_in_meters, self[:distance_in_meters]) if self[:distance_in_meters]
          xml << xml_value(:similarity, self[:name_similarity]) if self[:name_similarity]

          xml
        end

        # Returns the Apple plist representation of this category.  Represents a single category
        # object; needs to be wrapped in an XML document and an array or dict.
        def to_plist
          place_hash = {
            'id' => self.id,
            'name' => self.name.to_s,
            'created_at' => self[:created_at],
            'updated_at' => self[:updated_at],
            'latitude' => self.latitude,
            'longitude' => self.longitude,
            'elevation' => self[:elevation],
            'route' => self[:route],
            'route_length' => self[:route_length],
            'region' => self[:region],
            'region_area' => self[:region_area],
            'rating' => !self[:rating].blank? && self[:rating] || 0.0,
            'number_of_ratings' => !self[:number_of_ratings].blank? && self[:number_of_ratings] || 0,
            'score' => self[:score] || 0,
            'keywords' => self.tags,
            'center_of_collection' => self[:center_of_collection] || 'false'
          }

          place_hash['distance_in_meters'] = self[:distance_in_meters] if self[:distance_in_meters]
          place_hash['similarity'] = self[:name_similarity] if self[:name_similarity]

          place_hash['category'] = {
            'id' => self.category.id,
            'name' => self.category.name,
          }

          place_hash['details'] = details.to_hash

          place_hash['created_by'] = self.creator && self.creator.visible_for?(self) && self.creator.to_hash || {}
          place_hash['contributors'] = (self.contributors.map { |c| c.visible_for?(self) && c.to_hash || {} }).compact

          place_hash.to_plist
        end

      end
    end
  end
end
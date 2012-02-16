module PublicEarth
  module Db
    
    # Look up geographic locations on a map, such as countries, states, and cities.  Looks for information 
    # from our internal index (Atlas::Geography), then from the Google Local and Google Geocoder APIs.  
    class Where < PublicEarth::Db::Base
      
      GOOGLE_LOCAL_URI = 'http://ajax.googleapis.com'
      GOOGLE_GEOCODER_URI = 'http://maps.google.com/maps/geo?'

      LOCAL_QUERY_STRING = '/ajax/services/search/local?v=1.0&q='
      GEOCODER_QUERY_STRING = "/maps/geo?key=#{$google_maps_key}&output=json&q="

      ZOOM_FROM_ACCURACY = [2, 4, 6, 10, 12, 12, 13, 13, 14, 15]
      ZOOM_TO_LL = [0, 0.025, 0.04, 0.06, 0.075, 0.09, 0.1, 1.0, 2.5, 5.0, 10.0]

      class << self
        # Look to the Google geocoders to find a place.
        #
        # TODO:  Support "near" -- boost places near the given place, such as "Dover, UK" over "Dover, PA" when
        # searching in the UK.
        def am_i(query, options)
          results = Atlas::Geography.where_am_i(query, options) || where_remote(query, near)
          return_best_result(results)
        end
        alias :am_i? :am_i
        
        # Tries the Google Geocoder.  If that fails, tries Google Local.
        def where_remote(query, near = nil)
          found = where_geocoder(query, near)
          !found.blank? && found || where_local(query)
        end
      
        # Perform the where search against the true-blue Google geocoder.
        def where_geocoder(query, near = nil)
          url = URI.parse GOOGLE_GEOCODER_URI
          near_query = nil
          if near && near.kind_of?(Hash)
            #near_query = "ll=#{near[:latitude]},#{near[:longitude]}&spn=#{near[:span_latitude]},#{near[:span_longitude]}&gl=#{near[:country]}" 
            #near_query = "ll=#{near[:latitude]},#{near[:longitude]}&spn=#{near[:span_latitude]},#{near[:span_longitude]}" 
            #near_query = "gl=UK"
          end
                  
          response = Net::HTTP.start(url.host, url.port) do |http|
            http.get("#{GEOCODER_QUERY_STRING}#{CGI.escape(query)}&#{near_query}")
          end

          results = JSON.parse(response.body)['Placemark']
        
          unless results.nil? || results.empty?
            results.map do |result|
              if result['AddressDetails'] && result['AddressDetails']['Accuracy'].to_i >= 0
                p = { :name => result['address'] }

                p[:address] = result['AddressDetails']['Country']['AdministrativeArea']['Locality']['Thoroughfare']['ThoroughfareName'] rescue nil
                p[:city] = result['AddressDetails']['Country']['AdministrativeArea']['Locality']['LocalityName'] rescue nil
                p[:region] = result['AddressDetails']['Country']['AdministrativeArea']['AdministrativeAreaName'] rescue nil
                p[:country] = result['AddressDetails']['Country']['CountryNameCode'] rescue nil
                p[:postal_code] = result['AddressDetails']['Country']['AdministrativeArea']['Locality']['PostalCode'] rescue nil
                p[:latitude] = result['Point']['coordinates'][1].to_f rescue nil
                p[:longitude] = result['Point']['coordinates'][0].to_f rescue nil
                p[:accuracy] = result['AddressDetails']['Accuracy'].to_i rescue nil
                p[:zoom] = ZOOM_FROM_ACCURACY[result['AddressDetails']['Accuracy'].to_i] #rescue 0

                p
              else
                nil
              end
            end
          else
            []
          end
        end
      
        # Find the place matching the given term or terms, e.g. "Boulder" should match Boulder, CO.
        # Returns a hash of name, city, region, country, address, postal code, latitude, and longitude.
        def where_local(query)
          begin
            url = URI.parse GOOGLE_LOCAL_URI
            response = Net::HTTP.start(url.host, url.port) do |http|
              http.get(LOCAL_QUERY_STRING + CGI.escape(query))
            end

            results = JSON.parse(response.body)['responseData']['results']
          
            unless results.blank?
              results.map do |result|
                result['staticMapUrl'] =~ /zl=(\d+)/
                {
                  :name => result['titleNoFormatting'],
                  :city => result['city'],
                  :region => result['region'],
                  :country => result['country'],
                  :address => result['streetAddress'],
                  :postal_code => result['postalCode'],
                  :latitude => result['lat'].to_f,
                  :longitude => result['lng'].to_f,
                  :zoom => $1.to_i
                }
              end
            else
              []
            end
          rescue
            []
          end
        end
      
        def return_best_result(results)
          return nil if results.blank? || results.first.nil?
          build_where(results.first)
        end
      
        def build_where(result)
          
          if result[:accuracy]
            radius = ZOOM_TO_LL[10 - result[:accuracy].to_i]
            score = (15.0 - result[:accuracy].to_i) / 10.0
            sw_lat = result[:latitude] - radius
            sw_lng = result[:longitude] - radius
            ne_lat = result[:latitude] + radius
            ne_lng = result[:longitude] + radius
          else
            score = result['score']
            
            bounds = Polygon.from_ewkt doc['bounds']
            sw = bounds.envelope.lower_corner
            ne = bounds.envelope.upper_counter
            sw_lat = sw.y
            sw_lng = sw.x
            ne_lat = ne.y
            ne_lng = ne.x
          end
                
          Where.new(
            :name => result['name'] || result[:name],
            :score => score,
            :accuracy => result[:accuracy],
            :sw => {
              :latitude => sw_lat.to_f,
              :longitude => sw_lng.to_f,
            },
            :ne => {
              :latitude => ne_lat.to_f,
              :longitude => ne_lng.to_f
            }
          )
        end
      end
      
      # Return the standard formatted bounds.
      def bounds
        {
          :sw => self.sw,
          :ne => self.ne
        }
      end
      
      def initialize(attributes = {})
        super(attributes.reverse_merge(:type => "geography"))
        @attributes[:latitude] = (sw[:latitude] + ne[:latitude]) / 2
        @attributes[:longitude] = (sw[:longitude] + ne[:longitude]) / 2
      end
      
      def to_json
        @attributes.to_json
      end
      
      def to_plist
        @attributes.to_plist
      end
      
      def to_xml
        xml = XML::Node.new('where')

        xml << xml_value(:name, self[:name])
        xml << xml_value(:score, self[:score])
        xml << xml_value(:type, self[:type])
        
        if (self[:sw])
          sw = XML::Node.new('sw')
          sw << xml_value(:latitude, self[:sw][:latitude]) 
          sw << xml_value(:longitude, self[:sw][:longitude]) 
          xml << sw
        end
        
        if (self[:ne])
          ne = XML::Node.new('sw')
          ne << xml_value(:latitude, self[:ne][:latitude]) 
          ne << xml_value(:longitude, self[:ne][:longitude]) 
          xml << ne
        end

        xml
      end
      
    end
  end
end
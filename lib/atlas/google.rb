module Atlas
  class Google

    GOOGLE_GEOCODER_URI = 'http://maps.google.com/maps/geo?'
    
    if RAILS_ENV == 'production'
      GEOCODER_QUERY_STRING = "/maps/geo?client=gme-publicearth&amp;sensor=false&output=json&q="
    else
      GEOCODER_QUERY_STRING = "/maps/geo?key=#{$google_maps_key}&output=json&q="
    end
  
    # Perform the where search against the true-blue Google geocoder.
    def self.where_am_i(query, options = {})
      url = URI.parse GOOGLE_GEOCODER_URI
      near_query = []
      
      # Influence based on map view?
      if options[:bounds]
        near = Atlas::Geography.center(options[:bounds])
        near[:span_latitude] = (options[:bounds][:ne][:latitude] - options[:bounds][:sw][:latitude]).abs
        near[:span_longitude] = (options[:bounds][:ne][:longitude] - options[:bounds][:sw][:longitude]).abs
        near_query << "ll=#{near[:latitude]},#{near[:longitude]}&spn=#{near[:span_latitude]},#{near[:span_longitude]}" 

        unless options[:country]
          options[:country] = Atlas::Geography.connection.select_value("
            select abbr.label from geographic_synonyms abbr, geographies country, geographic_regions r 
            where 
              abbr.what = 'Abbreviation' and country.what = 'Country' and 
              country.id = abbr.geography_id and country.id = r.geography_id and 
              r.region && st_setsrid(st_makepoint(#{near[:longitude]}, #{near[:latitude]}), 4326) and
              st_within(st_setsrid(st_makepoint(#{near[:longitude]}, #{near[:latitude]}), 4326), r.region) limit 1;
          ")
        end
        near_query << "gl=#{options[:country]}" if options[:country].present?
      end

      near_query = near_query.join('&')
      
      response = Net::HTTP.start(url.host, url.port) do |http|
        http.get("#{GEOCODER_QUERY_STRING}#{CGI.escape(query)}&#{near_query}")
      end
      
      result = JSON.parse(response.body)
      if result['Status']
        if result['Status']['code'] == 200
          where = result['Placemark']
          where.map! do |placemark|
            if placemark['ExtendedData'] && placemark['ExtendedData']['LatLonBox'] && placemark['address']
              g = Atlas::Geography.new :label => placemark['address']
              g.readonly!
              g.write_attribute(:bounds, google_to_georuby(placemark['ExtendedData']['LatLonBox']))
              g.accuracy = placemark['AddressDetails']['Accuracy']
              g
            else
              nil
            end
          end
          
          # So it looks like a geography search results, when it's really not...
          where.instance_eval do
            def models
              self
            end
          end
          
          where.compact!
          
        # Too many requests!  Alert the fire department!
        elsif result['Status']['code'] == 620
          ActiveRecord::Base.logger.error("DANGER, WILL ROBINSON!  WE HAVE HIT THE GOOGLE GEOCODING LIMIT!")
        end
      end
        
      {:query => query, :where => where}
    end
  
    # Convert the LatLonBox from the Google Geocoder into a GeoRuby Polygon.
    def self.google_to_georuby(latlonbox)
      north = latlonbox['north']
      east = latlonbox['east']
      south = latlonbox['south']
      west = latlonbox['west']
      Polygon.from_coordinates([[[west, south], [west, north], [east, north], [east, south], [west, south]]], Atlas::Place::SRID)
    end
    
  end
end
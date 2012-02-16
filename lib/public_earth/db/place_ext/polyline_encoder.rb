# Douglas-Peucker polygon simplification algorithm passed through google's
# polyline encoding algorithm - fast routes :)
#
# SEE: http://code.google.com/apis/maps/documentation/polylinealgorithm.html
#      http://en.wikipedia.org/wiki/Ramer-Douglas-Peucker_algorithm
#
#     * num_levels and zoom_factor 
#       - indicate how many different levels of magnification the 
#       - polyline has and the change in magnification between those levels,
#
#     * very_small indicates the length of a barely visible object at the highest zoom level
#     * force_endpoints indicates whether or not the  endpoints should be visible at all zoom levels. 
module PublicEarth
  module Db
    module PlaceExt
      class PolylineEncoder
        attr_reader :encoded_points, :encoded_levels, :encoded_points_literal, :zoom_factor, :num_levels
         
        def initialize(options = {})
          @num_levels = options[:num_levels] || 9
          @zoom_factor = options[:zoom_factor] || 4
          @very_small = options[:very_small] || 0.00008
          @force_endpoints = options[:force_endpoints] || true
          @zoom_level_breaks = Array.new
          for i in 0 .. @num_levels do
            @zoom_level_breaks[i] = @very_small * (@zoom_factor ** (@num_levels-i-1))
          end
        end
          
        # Douglas-Peucker algorithm, adapted for encoding. 
        # Rather than eliminating points, record their distance 
        # from the segment which occurs at that step.
        # Distances are then converted to zoom levels.
        def dp_encode(points)
          points = parse_polyline_string(points)
          abs_max_dist = 0
          stack = []
          dists = []
          max_dist, max_loc, temp, first, last, current = nil
         
          if points.length > 2
            stack.push([0, points.length-1])
            while stack.length > 0 
              current = stack.pop
              max_dist = 0
              segment_length = (points[current[1]][:lat] - points[current[0]][:lat]) ** 2 + (points[current[1]][:lng] - points[current[0]][:lng]) ** 2
                
              i = current[0] + 1
              while i < current[1]
                temp = distance(points[i], points[current[0]], points[current[1]], segment_length)

                if temp > max_dist
                  max_dist = temp
                  max_loc = i
                  if max_dist > abs_max_dist
                    abs_max_dist = max_dist
                  end
                end
                i += 1
              end
                
              if max_dist > @very_small
                dists[max_loc] = max_dist
                stack.push([current[0], max_loc])
                stack.push([max_loc, current[1]])
              end

            end
          end

          @encoded_points = create_encodings(points, dists)
          @encoded_levels = encode_levels(points, dists, abs_max_dist)
          @encoded_points_literal = @encoded_points.gsub("\\", "\\\\\\\\")

          @encoded_points
        end
        
        private

        # Take the polyline string from the database and return
        # an array of point hashes
        def parse_polyline_string(polyline_string)
          points = []
          polyline_string[1..-1].gsub(/\(/, '').split('),').each do |point|
            tmp = point.split(',')
            points << { :lat => tmp[0].to_f, :lng => tmp[1].to_f }
          end

          points
        end

        # return the distance between the point p0 and the segment [p1, p2].
        def distance(p0, p1, p2, segment_length)
          if p1[:lat] == p2[:lat] and p1[:lng] == p2[:lng]
            out = Math.sqrt(((p2[:lat] - p0[:lat]) ** 2) + ((p2[:lng] - p0[:lng]) ** 2))
          else
            u = ((p0[:lat] - p1[:lat]) * (p2[:lat] - p1[:lat]) + (p0[:lng] - p1[:lng]) * (p2[:lng] - p1[:lng])) / segment_length
            if u <= 0
              out = Math.sqrt( ((p0[:lat] - p1[:lat]) ** 2 ) + ((p0[:lng] - p1[:lng]) ** 2) )
            end
            if u >= 1
              out = Math.sqrt(((p0[:lat] - p2[:lat]) ** 2) + ((p0[:lng] - p2[:lng]) ** 2))
            end
            if 0 < u and u < 1
              out = Math.sqrt( ((p0[:lat] - p1[:lat] - u * (p2[:lat]-p1[:lat])) ** 2) +
                ((p0[:lng] - p1[:lng] - u * (p2[:lng] - p1[:lng])) ** 2) )
            end
          end

          out
        end
          
        # Very similar to http://code.google.com/apis/maps/documentation/polylinealgorithm.html
        def create_encodings(points, dists)
          plat = 0
          plng = 0
          encoded_points = ""
           for i in 0 .. points.length do
            if !dists[i].nil? || i == 0 || i == points.length-1 
              point = points[i]
              lat = point[:lat]
              lng = point[:lng]
              late5 = (lat * 1e5).floor
              lnge5 = (lng * 1e5).floor
              dlat = late5 - plat
              dlng = lnge5 - plng
              plat = late5
              plng = lnge5
              encoded_points << encode_signed_number(dlat) + 
                encode_signed_number(dlng)
            end
          end

          encoded_points
        end
          
        # This computes the appropriate zoom level of a point in terms of it's 
        # distance from the relevant segment in the DP algorithm.
        def compute_level(dd)
          lev = 0
          if dd > @very_small
            while dd < @zoom_level_breaks[lev]
              lev += 1
            end
            return lev
          end
        end
          
        # Now we can use the previous function to march down the list
        # of points and encode the levels.  Like create_encodings, 
        # ignore points whose distance is undefined.
        def encode_levels(points, dists, absMaxDist)
          encoded_levels = ""
          if @force_endpoints
            encoded_levels << encode_number(@num_levels-1)
          else
            encoded_levels << encode_number(@num_levels-compute_level(abs_max_dist)-1)
          end
          for i  in 1 .. points.length-1
            if !dists[i].nil?
              encoded_levels << encode_number(@num_levels-compute_level(dists[i])-1)
            end
          end
          if @force_endpoints
            encoded_levels << encode_number(@num_levels-1)
          else
            encoded_levels << this.encode_number(@num_levels-compute_level(abs_max_dist)-1)
          end

          encoded_levels
        end
          
        # Very similar to Google's, although it should handle double shashes.
        def encode_number(num)
          encode_string = ""
          while num >= 0x20
            next_value = (0x20 | (num & 0x1f)) + 63
            encode_string << next_value.chr
            num >>= 5
          end
          final_value = num + 63
          encode_string << final_value.chr

          encode_string
        end
          
        # This one is Google's verbatim.
        def encode_signed_number(num)
          sgn_num = num << 1
          if num < 0
            sgn_num = ~(sgn_num)
          end

          encode_number(sgn_num)
        end
      end
    end
  end
end

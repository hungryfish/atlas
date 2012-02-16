module Atlas
  module Util
    
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
    class PolylineEncoder
      attr_reader :encoded_points, :encoded_levels, :encoded_points_literal, :zoom_factor, :num_levels

      LAT = 0
      LNG = 1
      
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
      # 
      # Points are expected to come in as an array of hashes, [{LAT => ..., LNG => ...},...]
      def dp_encode(points)
        abs_max_dist = 0
        stack = []
        dists = []
        max_dist, max_loc, temp, first, last, current = nil

        if points.length > 2
          stack.push([0, points.length-1])
          while stack.length > 0 
            current = stack.pop
            max_dist = 0
            segment_length = (points[current[1]][LAT] - points[current[0]][LAT]) ** 2 + (points[current[1]][LNG] - points[current[0]][LNG]) ** 2

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

      # return the distance between the point p0 and the segment [p1, p2].
      def distance(p0, p1, p2, segment_length)
        if p1[LAT] == p2[LAT] and p1[LNG] == p2[LNG]
          out = Math.sqrt(((p2[LAT] - p0[LAT]) ** 2) + ((p2[LNG] - p0[LNG]) ** 2))
        else
          u = ((p0[LAT] - p1[LAT]) * (p2[LAT] - p1[LAT]) + (p0[LNG] - p1[LNG]) * (p2[LNG] - p1[LNG])) / segment_length
          if u <= 0
            out = Math.sqrt( ((p0[LAT] - p1[LAT]) ** 2 ) + ((p0[LNG] - p1[LNG]) ** 2) )
          end
          if u >= 1
            out = Math.sqrt(((p0[LAT] - p2[LAT]) ** 2) + ((p0[LNG] - p2[LNG]) ** 2))
          end
          if 0 < u and u < 1
            out = Math.sqrt( ((p0[LAT] - p1[LAT] - u * (p2[LAT]-p1[LAT])) ** 2) +
              ((p0[LNG] - p1[LNG] - u * (p2[LNG] - p1[LNG])) ** 2) )
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
            lat = point[LAT]
            lng = point[LNG]
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
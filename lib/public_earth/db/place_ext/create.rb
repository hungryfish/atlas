module PublicEarth
  module Db
    module PlaceExt
      
      # Methods for creating places in the database.
      #
      # The methods in this module will be incorporated into the Place model at the class level, rather
      # than included as instance methods.
      module Create
        
        # PublicEarth::Db::Place.create(params[:place])
        def create(attributes)
          logger.debug(attributes)

          if attributes[:region_vertexes] =~ /\(/
            create_region(attributes)
          elsif attributes[:route_vertexes] =~ /\(/
            create_route(attributes)
          else
            create_point(attributes)
          end
        end
        
        # Create a new point on the map.  Requires a name (need not be unique), a primary category, and a 
        # latitude and longitude, and a source_data_set_id.  May also include original_id, original_uri,
        # and priority in the source data set.
        def create_point(attributes)
        
          unless attributes[:source_data_set_id]
            attributes[:source_data_set_id] = attributes[:source_data_set] && attributes[:source_data_set].id || nil
          end
        
          attributes[:category] ||= attributes[:category_id] 
          attributes[:category] = attributes[:category].id if attributes[:category].kind_of? PublicEarth::Db::Category
         
          place = new(one.create_point(
            nil,
            attributes[:name],
            attributes[:latitude] && attributes[:latitude].to_f || nil,
            attributes[:longitude] && attributes[:longitude].to_f || nil,
            attributes[:original_id],
            attributes[:original_uri],
            attributes[:priority],
            attributes[:category],
            attributes[:source_data_set_id],
            attributes[:elevation] && attributes[:elevation].to_i || nil,
            attributes[:is_visible].nil? && true || attributes[:is_visible]
          ))
          
          place.created = 'point'
          
          # Create the name attribute...
          place.details.from attributes[:source_data_set_id]
          place.details.name = attributes[:name]
          place.details.save

          place
        end
            
        # Create a new region on the map.  Requires a name (need not be unique), a primary category, 
        # region_vertexes , and a source_data_set_id.
        def create_region(attributes)
        
          unless attributes[:source_data_set_id]
            attributes[:source_data_set_id] = attributes[:source_data_set] && attributes[:source_data_set].id || nil
          end
        
          attributes[:category] ||= attributes[:category_id] 
          attributes[:category] = attributes[:category].id if attributes[:category].kind_of? PublicEarth::Db::Category
          
          place = new(one.create_region(
              nil, 
              attributes[:name], 
              attributes[:region_vertexes] || nil,  
              attributes[:original_id], 
              attributes[:original_uri], 
              attributes[:priority],
              attributes[:category],
              attributes[:source_data_set_id],
              attributes[:is_visible] || true
            ))
           
          place.created = 'region'
             
          # Create the name attribute...
          place.details.from attributes[:source_data_set_id]
          place.details.name = attributes[:name]
          place.details.save
          
          place
        end
        
                 
        # Create a new route on the map.  Requires a name (need not be unique), a primary category, 
        # route_vertexes, and a source_data_set_id.
        def create_route(attributes)
        
          unless attributes[:source_data_set_id]
            attributes[:source_data_set_id] = attributes[:source_data_set] && attributes[:source_data_set].id || nil
          end
        
          attributes[:category] ||= attributes[:category_id] 
          attributes[:category] = attributes[:category].id if attributes[:category].kind_of? PublicEarth::Db::Category

          place = new(one.create_route(
              nil, 
              attributes[:name], 
              attributes[:route_vertexes] || nil,
              attributes[:original_id], 
              attributes[:original_uri], 
              attributes[:priority],
              attributes[:category],
              attributes[:source_data_set_id],
              attributes[:is_visible] || true
            ))
              
          place.created = 'route'
          
          # Create the name attribute...
          place.details.from attributes[:source_data_set_id]
          place.details.name = attributes[:name]
          place.details.save
          
          place
        end

        # Return a unique slug based on the name, category, city, and country.  This slug is guaranteed to be
        # unique at the time it was generated, but it may not remain so, as the slug is not reserved in the
        # database in any way. (TODO?)
        def generate_slug(name, category_id, city, country) 
          one.generate_slug(name, category_id, city, country).values.first
        end
        
        # Used to generate missing slugs for places.  Not used in general production.  See lib/place_migration.rb.
        def generate_1000_slugs
          one.generate_1000_slugs
        end
        
      end
    end
  end
end
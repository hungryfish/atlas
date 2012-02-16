module PublicEarth
  module Db
    module Helper
      
      module GeneralFind

        # Call this method to look for a place, category, or source by ID, if you just have the ID.  The 
        # IDs are unique across all of PublicEarth, so we can make a few queries to look up information
        # in general, based on just the ID.  
        def find_in_general(id)
          case PublicEarth::Db::Base.connection.select_value("select * from what_is_uuid('#{id.gsub(/[^\w\-]/, '')}')")
          when 'places'
            PublicEarth::Db::Place.find_by_id(id)
          when 'categories'
            PublicEarth::Db::Category.find_by_id(id)
          when 'attribute_definitions'
            PublicEarth::Db::Attribute.find_by_id(id)
          when 'sources'
            PublicEarth::Db::Source.find_by_id(id)
          when 'users'
            PublicEarth::Db::User.find_by_id(id)
          when 'photos'
            PublicEarth::Db::Photo.find_by_id(id)
          when 'collections'
            PublicEarth::Db::Collection.find_by_id(id)
          end
        end
        
      end
    end
  end
end
module Atlas
  class CollectionPlace < ActiveRecord::Base

    has_many :places, :class_name => "Atlas::Place"
    
    class << self
      
      # Return the collections with the given common name that contain places.
      def called(name, limit = 3)
        collection_ids = CollectionPlace.connection.select_values("select collection_id from 
            collection_places, collections where collection_id = collections.id and 
            collections.name = '#{name.gsub(/'/, "''"}' limit #{limit}")
        connection.select_all "select * from collections where id in ()"
      end
      
    end

    # Returns the PublicEarth::Db::Collection, rather than an Atlas::Collection.
    #
    # TODO:  Finish conversion of PublicEarth::Db::Collection to Atlas::Collection.
    def collection
      @collection ||= PublicEarth::Db::Collection.find_by_id!(collection_id)
    end
    
  end
end
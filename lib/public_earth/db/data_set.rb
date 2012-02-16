module PublicEarth
  module Db

    class DataSet < PublicEarth::Db::Base
      
      attr_writer :source
   
      class << self
      
        def create(source) 
          results = new(one.create(source.id))
          results.source = source
          results
        end
      
        # Look up a data set for the given user.  If one does not exist, it is created (along with a source).
        def for_user(id)
          user = nil
          if id.kind_of?(Atlas::User) || id.kind_of?(PublicEarth::Db::User)
            user = id
            id = user.id
          end
          results = new(one.for_user(id))
          results.source = user.source if user
          results
        end

        # Look up a data set for the given user.  If one does not exist, it is created (along with a source).
        def for_source(id)
          new(one.for_source(id))
        end
      
        def for_anonymous(ip_address, session_id)
          new(one.for_anonymous(ip_address, session_id))
        end
        
      end # class << self

      # Backout all places for this source data set
      def delete
        PublicEarth::Db::Place.each_with_details_by_data_set(self) do |place|
          place.delete(self, false)
        end
        PublicEarth::Db::Place.solr_server.commit
      end
    
      def source
        @source ||= PublicEarth::Db::Source.find_by_id!(self.source_id)
      end
    end
  end
end
module Atlas
  module Extensions
    module Place
      class PlaceResults < PublicEarth::Search::Solr::Results

        # Return the documents as lightweight Place models.  These are only for displaying results;
        # they do not contain nor interact with the full database Place models in any way.
        def models
          @models ||= (documents.map do |doc| 
            # Atlas::Place.find(:first, :conditions => {:id => doc['id']}, :include => [:category, :place_attributes]) # from_search_document doc 
            Atlas::Place.from_search_document doc
          end).compact
        end
        
      end
    end
  end
end
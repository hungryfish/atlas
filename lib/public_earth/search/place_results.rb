require 'ostruct' 
require 'json'

module PublicEarth
  module Search
    class PlaceResults < Solr::Results
      
      # Return the documents as lightweight Place models.  These are only for displaying results;
      # they do not contain nor interact with the full database Place models in any way.
      def models
        @models ||= documents.map do |doc| 
          Atlas::Place.from_search_document doc 
        end
      end

    end
  end
end

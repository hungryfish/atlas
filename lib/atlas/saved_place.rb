module Atlas
  class SavedPlace < ActiveRecord::Base
    belongs_to :user, :class_name => 'Atlas::Place'
    belongs_to :place, :class_name => 'Atlas::Place'

    # default_scope :conditions => 'saved_places.place_id not in (select id from deletions)'
    default_scope :conditions => "not exists(select 1 from deletions where saved_places.place_id = deletions.id)"
    
    # Either creates a new saved place entry in the database for the given user, or just updates its
    # updated_at value if the entry already exists.  
    def self.create_or_update(user_id, place_id)
      existing = Atlas::SavedPlace.find(:first, :conditions => {:user_id => user_id, :place_id => place_id})
      if existing
        existing.updated_at = nil
        existing.save!
      else
        existing = Atlas::SavedPlace.create!(:user_id => user_id, :place_id => place_id)
      end
      PublicEarth::Db::Place.find_from_search(existing.place_id).first
    end
    
    # Get the saved places from the search engine for the given user ID.
    def self.for_user(user_id)
      PublicEarth::Db::Place.find_from_search(find(:all, :conditions => { :user_id => user_id }, :order => "updated_at desc").map(&:place_id))
    end

    def self.number_for(user_id)
      count(:conditions => {:user_id => user_id})
    end
    
    # Return the most recently saved places for the given user.  Defaults to 4 results.
    def self.recently_saved(user_id, limit = 4)
      with_scope(:find => { :limit => limit }) do
        Atlas::SavedPlace.for_user(user_id)
      end
    end
    
    # Go through the list of places and mark any as saved that are saved to this user.
    def self.flag_as_saved(user_id, places) 
      matching_places = Atlas::SavedPlace.find(:all, :conditions => ["user_id = ? and place_id in (?)", user_id, places.map(&:id)]).map(&:place_id)
      places.each { |place| place.saved_by_user = matching_places.include?(place.id) }
      places
    end
  end
end
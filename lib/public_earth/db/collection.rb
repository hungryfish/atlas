require 'public_earth/db/collection_ext/formats'
require 'public_earth/db/collection_ext/query_manager/what'
require 'public_earth/db/collection_ext/query_manager/query'
require 'public_earth/db/collection_ext/query_manager/query_field'

module PublicEarth
  module Db
    # Manage user collections of places
    class Collection < PublicEarth::Db::Base

      is_searchable
      set_solr_index 'collections'

      include PublicEarth::Db::CollectionExt::Formats         # output formats:  JSON, XML, etc.

      module StoredProcedures
        
        def self.create(source_id, name, what, slug = nil, description = nil, icon = nil)
          PublicEarth::Db::Collection.one.create(name, description, icon, what, slug, source_id)
        end
        
        def self.update(id, name, what, slug = nil, description = nil, icon = nil)
          PublicEarth::Db::Collection.one.update(id, name, description, icon, what, slug)
        end
        
        def self.delete(id)
          PublicEarth::Db::Collection.one.delete(id)
        end

      end

      find_many :user, :source, :slug

      class << self

        # For backwards compatibility...
        alias :for_user :find_by_user
        alias :for_source :find_by_source
        
        # Pass a Source or User into :created_by to associate the collection with a person or partner.  Otherwise
        # created_by_id should be set to a source ID.
        def create(attributes)
          attributes[:created_by] = attributes[:created_by].source if attributes[:created_by].kind_of? Atlas::User
          attributes[:created_by_id] = attributes[:created_by].id if attributes[:created_by].kind_of? Atlas::Source
          collection = new(attributes)
          collection.save!
        end
        
        # Delete the collection based on its ID.
        def delete(id)
          StoredProcedures.delete(as_id(id))
        end
        
        # Wipes out non-alphanumeric and dash characters from an ID string, so that we can safely pass it into a
        # search query.
        def clean_for_search(id)
          id.gsub(/[^\w\-]/, '')
        end
        
        # Load up the places for the given collection.  Gets the IDs from the database, then the places denormalized
        # from the search index.  Used internally by the Collection class; you shouldn't need to use this method 
        # externally.
        def places(collection_id)
          PublicEarth::Db::Place.find_from_search(*(PublicEarth::Db::Place.many.in_collection(collection_id).map { |result| result['in_collection'] }))
        end
        
        # Find the collections that contain the given place.  Defaults to the first 25 results.
        def containing(place_id, start = 0, limit = 25)
          place_id = clean_for_search(as_id(place_id))
          results = PublicEarth::Db::Collection.search_for("place_id:#{place_id}", :qt => 'standard', 
              :start => start && start.to_i, :rows => limit && limit.to_i > 0 && limit.to_i || 25)
          results.models
        end
        
        # Get a number of featured collections, i.e. collections with their ID in the featured_collections
        # table.  You may indicate a number of collections to retrieve, and will get a random sampling of
        # them.
        def featured(limit = 3)
          many.featured(limit).map { |attributes| new(attributes) }
        end
        
        def recent(limit = 10)
          many.recent(limit).map { |attributes| new(attributes) }
        end
        
        # Does the the user have the given place in any of his or her collections.  You can pass in the source
        # and place objects or their IDs, whichever is easier.  Defaults to returning the first 25 results.
        def place_in_source_collection(source_id, place_id, start = 0, limit = 25)
          source_id = clean_for_search(as_id(source_id))
          place_id = clean_for_search(as_id(place_id))
          
          results = PublicEarth::Db::Collection.search_for("place_id:#{place_id} && created_by_id:#{source_id}", 
              :qt => 'standard', :start => start && start.to_i, :rows => limit && limit.to_i > 0 && limit.to_i || 25)
          results.models
        end
        
        # Query the Solr server.  Override to use CollectionResults instead of Solr::Results.
        def search_for(keywords, options = {})
          solr_server.find(keywords, options.merge(:results => PublicEarth::Search::CollectionResults))
        end
        
        # Load a collection from the search document, without ever hitting the database.
        def from_search(document)
          collection = new
          collection.attributes[:id] = document['id']
          collection.attributes[:name] = document['name']
          collection.attributes[:slug] = document['slug']
          collection.attributes[:icon] = document['icon']
          collection.attributes[:description] = document['description']
          collection.attributes[:created_at] = document['created_at']
          collection.attributes[:updated_at] = document['updated_at']
          collection.attributes[:created_by_id] = document['created_by_id']
          
          collection.attributes[:what] = PublicEarth::Db::CollectionExt::QueryManager::What.new(document['what'])

          # Legacy compatibility
          collection.places = PublicEarth::Db::Place.find_from_search(*document['place_id']) if document['what'].blank?
          
          collection
        end

        # First tries to just strip the non-alphanumeric characters out of the name, replace the spaces with 
        # dashes, then it tries adding index numbers to the end, e.g. -1, -2, -3, until it finds a unique slug.
        #
        # There is the remote possibility that between the time the slug is created and save is actually called,
        # the slug could be duplicated and the save fail.  Save takes this into account and tries a second time
        # with a new slug.
        #
        # Slugs will be only alphanumeric characters and dashes.  All other characters are invalid.
        def generate_slug(name)
          PublicEarth::Db::Collection.one.generate_slug(name)['generate_slug']
        end
        alias :create_slug :generate_slug

      end # class << self

      def initialize(attributes = {})
        super(attributes)
        self.what = PublicEarth::Db::CollectionExt::QueryManager::What.new(self.what) unless self.what.kind_of? PublicEarth::Db::CollectionExt::QueryManager::What
      end
      
      def what
        attributes[:what] ||= PublicEarth::Db::CollectionExt::QueryManager::What.new
      end
      
      # Set the name of the place, and if it hasn't been already set, update the slug as well.
      def name=(value)
        @attributes[:name] = value
        slug
        changed
        value
      end
      
      # The slug for this collection, based on the name.  Won't modify the slug if it already exists; you'll have
      # to set the slug to nil to have it regenerate.
      def slug
        @attributes[:slug] = @attributes[:name] && PublicEarth::Db::Collection.create_slug(@attributes[:name]) unless @attributes[:slug] 
        @attributes[:slug]
      end
      
      # Manually set the slug value, or set it to nil to regenerate it the next time slug is called.
      def slug=(value)
        changed
        @attributes[:slug] = value
      end
      
      # Places associated with this collection. 
      #
      # Options may be passed in to paginate results, or submit other where or sort options.
      #
      # You can override the default location by passing in a location in the options[:where] value,
      # to search around.  Some examples of valid locations:
      #
      #   * Pass in a string:  does a search for that place via the geocoder
      #   * Pass in a place:  creates a rough bounding box around that place
      #   * Pass in a hash with an :id:  look up the place and center a bounding box around the place
      #   * Pass in a hash with :latitude and :longitude:  create a bounding box around the point and return
      #   * Pass in a hash with :sw and :ne:  Convert the hash to a bounding box
      #
      # If the center is a Place and indicated to be included, the place will be returned in the data set,
      # flagged as "center_of_collection", e.g. place[:center_of_collection] == true.
      #
      # What is returned is a read-only list of places.  Do not try to manipulate this list and expect it
      # to save with the added or removed places!
      def places(options = {})
        if @places.nil? || !options.blank?
          
          # Upgrade the collection to a smart collection, i.e. store the places in the "what" field.
          if what.blank?
            @places = PublicEarth::Db::Collection.places(self.id)
            if @places.present?
              # Don't use self.add_place(@places); it'll reset @places!
              what.query.add(:places) << @places
            end
          else
            @places = what.search_for_places(options)
          end

        end
        
        massaged = @places
        
        # Do we need to include the center point?
        if what.center && what.center.kind_of?(Atlas::Place) && what.center[:center_of_collection]
          existing = massaged.find { |check| check.id == what.center.id }
          if existing
            existing.center_of_collection = true
          else
            what.center.center_of_location = true
            massaged.unshift what.center
          end
        end
        massaged
      end
      
      # Reset the cached places so they'll reload on the next request for places.
      def reset_places
        @places = nil
      end
      
      # Manually set the places associated with this collection.  Useful for caching the places in an action, 
      # or for collections with only places (formerly static collections).  This sets the places locally, it
      # does NOT modify the places tracked by this collection.  Mostly used to load places from the search
      # index for old-style static collections.
      def places=(value)
        @places = value
      end
      
      # Add a place to the collection.  You can pass in a place, and ID, many places and IDs.
      def add_place(*place)
        reset_places
        unless place.blank?
          what.query.add(:places) << place.flatten 
          changed
        end
      end
      
      # Remove a place from the collection.
      def remove_place(*place)
        reset_places
        unless place.blank?
          what.query[:places] && what.query[:places] >> place.flatten
          changed
        end
      end

      # Add a category to the collection.
      def add_category(*category)
        unless category.blank?
          what.query.add(:categories) << category.flatten
          changed
        end
      end
      
      # Remove a category from the collection.
      def remove_category(*category)
        unless category.blank?
          what.query[:categories] && what.query[:categories] >> category.flatten 
          changed
        end
      end
      
      # Add a source to the collection.
      def add_source(*source)
        unless source.blank?
          what.query.add(:sources) << source.flatten 
          changed
        end
      end
      
      # Remove a source from the collection.
      def remove_source(*source)
        unless source.blank?
          what.query[:sources] && what.query[:sources] >> source.flatten
          changed
        end
      end
      
      # Compare objects for equality by their id
      def ==(other)
        self.id == other.id
      end
      
      # Add any object to the collection.  Supports Place, Category, and Source.  Objects of any other type will
      # be ignored.
      # 
      # Returns this collection, so you can chain these calls if you like.  Or pass in an array of items. 
      def <<(*object)
        object = object.flatten
                
        # Convert any IDs (strings) into their correct objects.
        object.map! { |o| o.kind_of?(String) && PublicEarth::Db::Base.find_in_general(o) || o }
        object.compact!
        
        places = object.select { |o| o.kind_of? Atlas::Place }
        add_place(*places) unless places.blank?

        categories = object.select { |o| o.kind_of?(PublicEarth::Db::Category) || o.kind_of?(Atlas::Category)}
        add_category(*categories) unless categories.blank?
        
        sources = object.select { |o| o.kind_of? PublicEarth::Db::Source }
        add_source(*sources) unless sources.blank?
        
        self
      end
      
      # Remove an object from the collection.  Supports Place, Category, and Source, or just the string ID for 
      # any of them.
      def >>(*object)
        object = object.flatten
        
        # Convert any IDs (strings) into their correct objects.
        object.map! { |o| o.kind_of?(String) && PublicEarth::Db::Base.find_in_general(o) || o }
        object.compact!

        places = object.select { |o| o.kind_of?(Atlas::Place) }
        remove_place(*places) unless places.blank?

        categories = object.select { |o| o.kind_of?(PublicEarth::Db::Category) || o.kind_of?(Atlas::Category) }
        remove_category(*categories) unless categories.blank?
        
        sources = object.select { |o| o.kind_of?(PublicEarth::Db::Source) || o.kind_of?(Atlas::Source)}
        remove_source(*sources) unless sources.blank?
        
        self
      end
      
      # Rate this collection.
      def rate(rating, source)
        PublicEarth::Db::Collection.one.rate(self.id, rating, source.id)
        changed
        @rating = nil
      end
    
      # Returns the rating given by a source (which may include users).
      def rating_for_source(source)
        result = PublicEarth::Db::Collection.one.rating(self.id, source.id)
        result && result['rating'].to_f || nil
      end
      
      # Returns the average_rating and rating_count for the collection
      def rating
        return @rating if @rating
        result = PublicEarth::Db::Collection.one.rating(self.id)
        @rating = { :average_rating => result['average_rating'].to_f, :rating_count => result['rating_count'].to_i } rescue nil
      end
      
      # Who created this collection. Returns a source.
      def created_by
        @created_by ||= PublicEarth::Db::Source.find_by_id(@attributes[:created_by_id])
      end
      
      # Used internally to set the source that created this place.  It does not alter the database.
      def created_by=(value)
        @created_by = value
      end

      # Validate the object before save.  
      #
      # TODO: Need something nicer than this?!
      def validate
        raise "A name for the collection is required." unless @attributes[:name]
        raise "A source for the collection is required (created_by_id)." unless @attributes[:created_by_id]
      end
      
      # Does this model meet the business requirements for a collection?
      def valid?
        begin
          validate
          true
        rescue
          false
        end
      end
      
      # Raises an exception if the collection can't be saved.  Handles the three cases of creating,
      # updating, and deleting a collection, based on its state.
      #
      # If the save fails and the slug is nil, that means we couldn't come up with a unique slug.
      # Perhaps ask the user to enter in their own slug? (Ick)
      def save!(options = {})
        tries = 0
        
        Collection.transaction do
          what_to do |state|
            case state
            when :create
              validate
              begin
                results = StoredProcedures.create(
                    self.created_by_id,
                    self.name,
                    self.what.to_json,
                    self.slug,
                    @attributes[:description],
                    @attributes[:icon]
                  )
                self.id = results['id']
              
                # TODO: For 2.3.9
                # save_collection_places
              rescue
                # We do this in case the slug came back as a duplicate on save
                tries += 1
                self.slug = nil
                tries < 2 && retry || raise($!)
              end

            when :update
              validate
              StoredProcedures.update(
                  self.id, 
                  self.name,
                  self.what.to_json,
                  self.slug,
                  @attributes[:description],
                  @attributes[:icon]
                )

                # TODO: For 2.3.9
                # save_collection_places
            when :delete
              StoredProcedures.delete(self.id)
              self.solr_server.delete(self.id)
            end
          end
        end
        
        self
      end
      
      # Returns true if the save was successful, false if not.
      def save(options = {})
        trap_exception { save!(options) }
      end
      
      # Take any statically connected places in this collection and add them to the collection_places
      # table.  Allows the database to perform geo-based queries about collections.  These 
      # collection_places are not used anywhere by collections themselves (yet).
      def save_collection_places
        CollectionPlace.delete_all :conditions => ["collection_id = ?", self.id]
        inserts = (what.query[:places].values.map { |place_id| "('#{self.id}','#{place_id}')" }).join(",")
        CollectionPlace.connection.insert("insert into collection_places (collection_id, place_id) values #{inserts}")
      end
      
      # Shortcut to delete a photo.  Simply sets the deleted flag and calls save.  Raises an exception if
      # the save fails.
      def delete!
        deleted
        save!
      end
      
      # Shortcut to delete a photo.  Simply sets the deleted flag and calls save.  Returns false if the
      # save failed, true if it succeeded.
      def delete
        deleted
        save
      end

      # Adjust the boost of the collection in the search index, e.g. for ratings...
      def boost
        1.0 #self.rating / 2.0
      end
      
      def search_document
        document = {
          :id => self.id,
          :name => self.name,
          :description => self[:description],
          :created_by_id => self.created_by.id,
          :created_by_name => self.created_by.name,
          :number_of_places => self.places.length
        }

        document[:created_at] = Time.parse(@attributes[:created_at]).gmtime.xmlschema unless @attributes[:created_at].blank?
        document[:updated_at] = Time.parse(@attributes[:updated_at]).gmtime.xmlschema unless @attributes[:updated_at].blank?

        document[:what] = self.what.to_json
        
        if self.created_by.user?
          document[:created_by_username] = self.created_by.user.username
          document[:created_by_email] = self.created_by.user.email
        end

        unless what.categories.blank?
          # Compact the categories. There's no FK to ensure that they still exist.
          document[:category] = what.categories.compact.map { |c| c.name }
          document[:category_id] = what.categories.compact.map { |c| c.id }
        end
        
        unless what.sources.blank?
          document[:source_id] = what.sources.map { |s| s.id }
        end
        
        unless what.places.blank?
          document[:place] = what.places.map { |p| p.name }
          document[:place_id] = what.places.map { |p| p.id }
          document[:keyword] = (what.places.map { |p| p.tags.map { |t| t['name'] } }).flatten.uniq
        end
        
        document
      end
      
      def widget_references
        @widget_references ||= Atlas::Collection.find(self.id).widget_references
      end
    end
  end
end

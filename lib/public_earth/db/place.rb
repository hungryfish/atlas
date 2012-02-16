require 'json'
require 'fileutils'
require 'ostruct' 

require 'public_earth/db/place_ext/create'
require 'public_earth/db/place_ext/finders'
require 'public_earth/db/place_ext/formats'
require 'public_earth/db/place_ext/search'
require 'public_earth/db/place_ext/photo_manager'

module PublicEarth
  module Db
    class Place < PublicEarth::Db::Base

      include PublicEarth::Db::PlaceExt::Search      # integration with Solr
      include PublicEarth::Db::PlaceExt::Formats     # output formats:  JSON, XML, etc.

      extend PublicEarth::Db::PlaceExt::Create       # place creation
      extend PublicEarth::Db::PlaceExt::Finders       # looking up places
      
      attr_reader :total_comments
      attr_accessor :content_format
      
      # Returns the name of the place, preferably from the attributes, but defaults to the
      # value in the places table if there isn't one in the details.
      def name
        @name ||= details && details.name && details.name.to_s || @attributes[:name]
      end
      
      # This allows you to set the name of a place from something other than the details,
      # namely attributes, without having to load the details.  If you don't need the 
      # details, this can save you a DB hit.
      def name=(value)
        @name = value
      end
      
      # Access the place attributes.  Returns all attributes in order of priority, unless a category is
      # indicated.  In that case, return just the attributes associated with that category.
      def details(category_id = nil)
        @details ||= PublicEarth::Db::Details.new(self)
      end
    
      # Manually set the details.  You can use this if you need to reload the details, perhaps for a
      # specific category, or if you're loading mixed place/attributes results, such as each_with_details()
      # does.
      def details=(values) 
        @details = values
      end
      
      # Have the details been loaded yet?
      def details?
        !! @details
      end
      
      # Save place attributes.
      def save_details(attr, source_data_set)
        self.details.from(source_data_set)
        attr.each_pair do |k, v|
          self.details[k] = v
        end
        self.details.save
      end

      def delete(source_data_set=nil, autocommit=true)
        ds_name = source_data_set && " for #{source_data_set.name} (#{source_data_set.id})" || ""
        logger.info("Deleting #{self.details.name} (#{self.id}) #{ds_name}")
        
        transaction do 
          # Delete Photos for this place/source
          #
          # This may potentially delete photos loaded by another dataset, but
          # since photos are tied to a place and source, and not a dataset,
          # we have no way of knowing this. So, we error on the side of deleting
          # too much since the data will likely be reloaded at some point with
          # its photos.  
          self.photos.each do |p|
            if p.source_id == source_data_set.source.id
              p.remove_from_s3
              p.delete
            end
          end
        
          # Backout or completely delete a point, depending on if a source_data_set is provided
          # and based on whether the backout was clean
          if source_data_set.present?
            should_delete_permanently = !!(PublicEarth::Db::Place.one.delete_by_data_set(self.id, source_data_set.id)['delete_by_data_set'])
          else
            PublicEarth::Db::Place.one.delete(self.id)
            should_delete_permanently = true
          end

          # Delete point from search index
          if should_delete_permanently
            self.solr_server.delete(self.id, autocommit)          
          end
        
          # Delete history
          # If source data set is nil, all modern history for this place is removed. 
          PublicEarth::Db::History.delete(self, source_data_set)
        end
      end
      
      def sources
        @sources ||= PublicEarth::Db::Place.many.sources(self.id)
      end

      # Return the list of contributors to this place, i.e. users and other third-party sources that
      # have worked together to make this place great!  The first entry will be the same as the value
      # of the created_by method. 
      def contributors
        @contributors ||= PublicEarth::Db::Source.many.contributors(self.id).map { |c| PublicEarth::Db::Source.new(c) }
      end
      
      # Source account for the entity that created this place.
      def created_by
        @created_by ||= PublicEarth::Db::Source.creator_of self
      end

      # Returns the category defined in the category_id field of the places table.
      def category
        @category ||= PublicEarth::Db::Category.find_by_id(self.category_id)
      end
      
      # Manually set the category.
      def category=(category)
        self.category_id = category.id
        @category = category
      end
      
      # Return the collections this place is in.
      def collections
        @collections ||= PublicEarth::Db::Collection.containing(self.id)
      end
      
      # Return the head category.
      def head
        @attributes[:head] || self.category.head rescue nil
      end
      
      # Update category for this place.  Indicate the current user or source making the change, if you
      # would be so kind, so we can record the history.
      #
      # Also resets the details, so we get the correct attributes based on the new category.
      def update_category(category_id, current_user = nil)
        if (self.category && self.category.id != category_id)
          original_category = self.category
        
          # So we can reload the new category
          PublicEarth::Db::Place.one.update_category(self.id, category_id)
          @category = nil
          self.category_id = category_id

          # We only record a category change if the current user was provide.
          History.record(self, current_user).changed_category(self.category, original_category) if current_user

          @details = nil
        end
      end
    
      # Return the list of discussions for this place.
      def discussions
        discussions = []
        last_discussion = nil
        @total_comments = 0
        PublicEarth::Db::Place.many.comments(self.id).each do |attributes|
          if last_discussion.nil? || last_discussion.id != attributes['discussion_id']
          
            last_discussion = PublicEarth::Db::Discussion.new({
                :id => attributes['discussion_id'],
                :created_at => attributes['discussion_created_at'],
                :updated_at => attributes['last_commented_on_at'],
                :subject => attributes['subject'],
                :number_of_comments => attributes['number_of_comments']
              })
            discussions << last_discussion
          end
          if last_discussion.number_of_comments.to_i > 0
            @total_comments += 1
            last_discussion << PublicEarth::Db::Comment.new({
                :id => attributes['id'],
                :discussion_id => attributes['discussion_id'],
                :user_id => attributes['user_id'],
                :user_email => attributes['user_email'],
                :content => attributes['comment'],
                :created_at => attributes['comment_created_at']
              })
          end
        end

        discussions
      end
    
      def total_comments
        @total_commments || (discussions && @total_comments)
      end
      
      # Return the photo manager for the place.  By default, this will act like a collection of photos.
      # Also has tools to add and update photos and modifications.
      def photos
        @photo_manager ||= PublicEarth::Db::PlaceExt::PhotoManager.new(self)
      end
      alias :photo_manager :photos
      
      # Rate this place.
      def rate(rating, source)
        PublicEarth::Db::Place.one.rate(self.id, rating, source.id)
        @rating = nil
      end
    
      #  Returns the rating given by a source (which may include users).
      def rating_for_source(source)
        result = PublicEarth::Db::Place.one.rating(self.id, source.id)
        result && result['rating'].to_f || nil
      end
      
      # Returns the average_rating and rating_count for the place
      def rating
        return @rating if @rating
        result = PublicEarth::Db::Place.one.rating(self.id)
        @rating = { :average_rating => result['average_rating'].to_f, 
          :rating_count => result['rating_count'].to_i } rescue nil
      end
    
      # Return attribute values
      def tags
        @tags ||= PublicEarth::Db::Place.many.tags(self.id).map { |hash| Tag.new(hash) }
      end
      alias :keywords :tags
      
      # This sets the tags locally in the object (cache); it does not modify the database.
      def tags=(set_of_tags)
        @tags = set_of_tags.nil? && nil || set_of_tags.sort
      end
      alias :keywords= :tags=
      
      def tag_labels(tags)
        tags.map(&:name)
      end
      
      # Save tags (keywords/tags) to place details.  If you pass in a nil value for tags, the request is
      # ignored.  If you pass in an empty string, the keywords are cleared!
      #
      # Keywords may only contain letters, numbers, en dashes '-', #, &, and !
      def save_tags(tags, source_data_set)
        #return unless tags.match(/^[a-zA-Z0-9,\-\s#&!']*$/)
        return if tags.nil?
        
        source_data_set = source_data_set.data_set if source_data_set.respond_to? :data_set
        
        new_tags = (tags.split ',').compact.uniq.map { |tag_name| tag_name.strip.downcase }.reject { |tag| tag.blank? || !tag.match(/^[a-zA-Z0-9\-\s]*$/) }
        existing_tags = self.tags.map { |tag| tag.name.downcase }

        to_add = new_tags - existing_tags
        to_remove = existing_tags - new_tags
        
        added = PublicEarth::Db::Place.many.add_tags(self.id, "{#{to_add.join(',')}}", 
            source_data_set.id).map { |hash| Tag.new(hash) }
            
        removed = PublicEarth::Db::Place.many.remove_tags(self.id, "{#{to_remove.join(',')}}",
            source_data_set.id).map { |hash| Tag.new(hash) }

        # Record the changes, en masse.
        History.record(self, source_data_set) do |h|
          added.each do |added_tag|
            h.add_keyword(added_tag.name)
          end
          
          removed.each do |removed_tag|
            h.delete_keyword(removed_tag.name)
          end
        end
        
        self.tags += added
        self.tags.delete_if { |tag| removed.include?(tag) }
      end
      alias :save_keywords :save_tags

      # These tag methods are called in save_tags (and update_search_index is called there)
      def add_tag(tag_name, data_set)
        return if self.tags.include?(Tag.new(:name => tag_name))
        data_set = data_set.data_set if data_set.respond_to? :data_set
        self.tags += [Tag.new(PublicEarth::Db::Place.one.add_tag(self.id, tag_name, nil, data_set.id))]
      end
      alias :add_keyword :add_tag

      # Remove this tag.
      def remove_tag(tag_name, data_set)
        data_set = data_set.data_set if data_set.respond_to? :data_set
        removed_tag = Tag.new(PublicEarth::Db::Place.one.remove_tag(self.id, tag_name, nil, data_set.id))
        self.tags.delete_if { |tag| tag.name.downcase == removed_tag.name.downcase }
      end
      alias :remove_keyword :remove_tag

      # Update the position of the place.  If latitude or longitude is blank, the request is ignored.
      def update_point(latitude, longitude, data_set_id)
        return if latitude.blank? || longitude.blank?
        data_set = data_set_id.kind_of?(PublicEarth::Db::DataSet) && data_set_id || PublicEarth::Db::DataSet.find_by_id(data_set_id)
        History.record(self, data_set).repositioned(self.latitude, self.longitude, latitude, longitude)
        PublicEarth::Db::Place.one.update_point(self.id, latitude.to_f, longitude.to_f, data_set.id)
        self.latitude = latitude.to_f
        self.longitude = longitude.to_f
      end

      def update_route(route, data_set_id)
        return if route.blank?
        data_set = data_set_id.kind_of?(PublicEarth::Db::DataSet) && data_set_id || PublicEarth::Db::DataSet.find_by_id(data_set_id)
        PublicEarth::Db::Place.one.update_route(self.id, route, data_set.id)
      end
       
      def update_region(region, data_set_id)
        return if region.blank?
        data_set = data_set_id.kind_of?(PublicEarth::Db::DataSet) && data_set_id || PublicEarth::Db::DataSet.find_by_id(data_set_id)
        PublicEarth::Db::Place.one.update_region(self.id, region, data_set.id)
      end
      
      # Returns Array of waypoints that represent either a route or region
      def waypoints
        # expecting something like "(#,#),(#,#),..."
        points = self.route.blank? && self.region || self.region.blank? && self.route 
        
        # produces "#,#),(#,#"
        chomped = points.chop.slice(1, points.length)
        
        # yields Array of Hashes [{:latitude => #, :longitude => #},...]
        chomped.split("),(").map do |pair|
          { :latitude => pair.split(",")[0], :longitude => pair.split(",")[1]}
        end
      end
      
      # HACK!  This retrieves the grouped list of possible features that user should be able to 
      # set the features attribute to.  Aggregates between the declared values in the features
      # table and those that have been assigned to the features attribute (in place_attribute_values).
      def features
        by_collection = Hash.new { |hash, key| hash[key] = [] }
        PublicEarth::Db::Place.many.features.each do |feature|
          by_collection[feature['collection']] << feature['feature']
        end
        by_collection
      end
      
      # Generate a unique slug for this place, via the database.  Does not save the slug, and does not 
      # guarantee the slug will remain unique!
      def generate_slug
        PublicEarth::Db::Place.generate_slug(name, category.id, details.city, details.country)
      end
      
      # Compare place IDs.
      def ==(place)
        self.id.eql?(place.id)
      end
       
      # Return the name of the place.
      def to_s
        self.name
      end     
    end
  end
end

require 'public_earth/db/category_ext/formats'

module PublicEarth
  module Db

    class Category < PublicEarth::Db::Base
      is_searchable
      set_solr_index 'categories'
      
      include PublicEarth::Db::CategoryExt::Formats

      finder :name
      
      class << self

        # Loads just the basic category information, no hierarchy or number of places.  Throws an exception if the
        # category doesn't exist.
        def find_by_id!(id)
          cache_manager.ns(:categories).get_or_cache(id, 24.hours) do 
            new(one.find_by_id(id))
          end
        end
        
        # Loads just the basic category information, no hierarchy or number of places.  Returns nil if the
        # category doesn't exist.
        def find_by_id(id)
          cache_manager.ns(:categories).get_or_cache(id, 24.hours) do 
            construct_if_found one.find_by_id_ne(id)
          end
        end

        # Create a new tag and flag it as a category.
        def create(id, name, data_set, language = nil)
          new(one.create(id, name, language, data_set.id))
        end
      
        # Delete a category by its name.  If the tag exists, the original tag information is returned.  Otherwise
        # returns nil.
        def delete(name, data_set)
          existing = one.delete(name, data_set.id)
          cache_manager.ns(:categories).delete(existing.id)
          reset_cache
          existing && new(existing) || nil
        end

        # Get child categories for the given category.
        def children(category_id = nil)
          PublicEarth::Db::Category.find_by_id!(category_id).children
        end
        
        # Return all the categories in the database, in alphabetical order.
        def all
          cache_manager.ns(:categories).get_or_cache(:all, 24.hours) do |key|
            many.all.map do |results| 
              category = PublicEarth::Db::Category.new(results)
            end
          end
        end
        alias :all_with_parents :all
        
        def head
          cache_manager.ns(:categories).get_or_cache(:head, 24.hours) do |key|
            head_categories = many.head.map do |results| 
              category = PublicEarth::Db::Category.new(results)
            end
            head_categories.sort_by{ |category| category.name }
          end
        end
        
        # Return all the categories that may be assigned places, i.e. have no children.
        def assignable
          cache_manager.ns(:categories).get_or_cache(:assignable, 24.hours) do |key|
            many.assignable().map do |results| 
              category = PublicEarth::Db::Category.new(results)
            end
          end
        end
        
        # Load the categories from the database en masse, then structure them in their
        # object models.  Returns a hash of all the categories, keyed off their IDs.
        def ontology
          cache_manager.ns(:categories).get_or_cache(:ontology, 24.hours) do
            ontology = Hash[*(all.map { |c| [c.id, c] }).flatten]
            children = Hash.new { |hash, key| hash[key] = [] }
            
            # Configure the parents
            ontology.each do |category_id, category|
              if category.parent_id
                category.parent = ontology[category.parent_id]
                children[category.parent_id] << category
              end
            end
            
            # Load the children
            children.each do |category_id, child_categories|
              ontology[category_id].children = child_categories
            end

            # Clear out the top level
            ontology.delete_if { |category_id, category| category.loaded? :parent }
            
            ontology
          end
        end
        
        # Call this to reset general caches of categories, like the set of all the categories, or the assignable
        # categories.
        def reset_cache
          cache_manager.ns(:categories).delete(:all)
          cache_manager.ns(:categories).delete(:assignable)
          cache_manager.ns(:categories).delete(:ontology)
        end
        
      end # class << self
    
      # Call this whenever categories are modified to reset the cache collections of categories (:all, :ontology, etc.)
      # and also update this object's information in the cache.  Returns self.
      def update_cache
        PublicEarth::Db::Category.reset_cache
        cache_manager.ns(:categories).put(self.id, self, 24.hours)
      end
            
      # Rename the category.  Updates the category information from the database.
      def rename(new_name, data_set)
        unless new_name == name
          @attributes = PublicEarth::Db::Category.one.rename(self.id, new_name, data_set.id)
          update_cache
        end
      end
    
      # Make this tag the child of the given parent category.  You can pass in either the Category object itself, or
      # just the ID of an existing category.  If the category doesn't exist, an exception will be raised.
      #
      # If either tag is not a category, it will be flagged as one by this method.
      #
      # Returns the parent tag object, if you'd like to chain the method.
      def add_parent(parent_category, data_set)  
        parent_category = PublicEarth::Db::Category.find_by_id(parent_category) if parent_category.kind_of?(String)
        PublicEarth::Db::Category.one.add_child(parent_category.id, self.id, data_set.id)
        cache_manager.ns(:categories).delete(parent_category.id)
        update_cache
        parent_category
      end

      # The opposite of parent().  Just calls parent() in reverse.  Returns the child category object, if you'd
      # like to chain the method.
      def add_child(child_category, data_set)
        child_category = PublicEarth::Db::Category.find_by_id(child_category) if child_category.kind_of?(String) 
        child_category.add_parent(self, data_set)
        child_category
      end

      # Remove the given child category from this category, acting as its parent.  Won't return anything, but will raise
      # an exception if there's a problem.
      def remove_child(child_category, data_set)
        child_category = PublicEarth::Db::Category.find_by_id(child_category) if child_category.kind_of?(String)
        PublicEarth::Db::Category.one.remove_child(self.id, child_category.id, data_set.id)
        update_cache
        cache_manager.ns(:categories).delete(self.id)
        cache_manager.ns(:categories).delete(self.id)
        child_category
      end

      # Return the collection of categories that this category is related to by a "kind of" relationship type.
      def children
        query_for :children do
          PublicEarth::Db::Category.many.children(self.id).map { |attributes| PublicEarth::Db::Category.new(attributes) }
        end
      end
      
      def children=(value)
        assign :children, value
      end
      
      # Return the collection of categories that this category is related to by a "kind of" relationship type.  This
      # is left over from the days when a category could have multiple parents.  Now it just returns the current
      # category parent as an array.
      def parents
        [parent]
      end

      def parent
        query_for :parent do 
          PublicEarth::Db::Category.find_by_id(self[:parent_id]) if self[:parent_id]
        end
      end
      
      def parent=(value)
        assign :parent, value
      end
      
      # Get all the categories this category is a child of (climb the tree).
      def belongs_to
        query_for :belongs_to do
          PublicEarth::Db::Category.many.belongs_to(self.id).map { |hash| PublicEarth::Db::Category.new(hash) }
        end
      end
      
      # Return the collection of places associated with this category.  This should ONLY be used for testing,
      # as it limits the number of places returned to 10.
      def places
        PublicEarth::Db::Category.many.places(self.id, 10).map { |attributes| PublicEarth::Db::Place.new(attributes) }
      end   
      
      #Return interesting places for the category. 'Interesting' currently meaning featured and highly rated. 
      def interesting_places(limit = 10, offset = 0)
        results = PublicEarth::Db::Place.search_for( '',
          :start => offset,
          :rows => limit,
          :fq => "(belongs_to:#{self.id})"
         )
         results.models
      end
      
      #Return the places changed most recently for this category.
      def recently_changed_places(limit = 10, offset = 0)
        results = PublicEarth::Db::Place.search_for( '', 
          :start => offset,
          :rows => limit,
          :fq => "(belongs_to:#{self.id})",
          :sort => 'timestamp desc'
         )
         results.models
      end
      
      #Return all places for this category sorted by name. This is for the leaf category pages.
      def all_places(limit = 10, offset = 0)
        results = PublicEarth::Db::Place.search_for( '',
          :start => offset,
          :rows => limit,
          :fq => "(belongs_to:#{self.id})",
          :sort => 'nameSort asc'
         )
         results.models
      end
      
      def num_places
        results = PublicEarth::Db::Place.search_for( '',
          :rows => 1,
          :fq => "(belongs_to:#{self.id})"
         )
         results.found
      end

      
      def hierarchy
        hierarchy = [self]
        
        if parent
          hierarchy += parent.hierarchy
        end
        
        hierarchy
      end
      
      # Find places in this category within the bounding box.  The bounding box should be a hash with two 
      # parameters, sw and ne, representing the corners of the bounding box.  Each parameter should have 
      # two hashes, with latitude and longitude values in them:
      #
      #   bounding_box = {
      #     :sw => { :latitude => 32.8, :longitude => -104.3 },
      #     :ne => { :latitude => 33.7, :longitude => -103.23 }
      #   }
      def places_within(bounding_box, limit = 10, offset = 0)
        PublicEarth::Db::Category.many.places(self.id, bounding_box[:sw][:latitude], bounding_box[:sw][:longitude], 
          bounding_box[:ne][:latitude], bounding_box[:ne][:longitude], limit, offset).map { |attributes| PublicEarth::Db::Place.new(attributes) }
      end

      # Return the number of places within this category in the given bounding box.  See places_within() for
      # details on the parameters.
      def number_of_places_within(bounding_box)
        PublicEarth::Db::Category.one.number_of_places(self.id, bounding_box[:sw][:latitude], bounding_box[:sw][:longitude], 
          bounding_box[:ne][:latitude], bounding_box[:ne][:longitude])['number_of_places'].to_i
      end
    
      # Associate an attribute definition with this category.
      def define_attribute(attribute_name, data_set, priority = 0, required = false, local = false)
        @attributes[:attribute_definitions] = PublicEarth::Db::Attribute.attributes_hash_from_records(
            PublicEarth::Db::Category.many.define_attribute(self.id, attribute_name, priority, required, local, data_set.id)
          )
        update_cache
        @attributes[:attribute_definitions]
      end
      alias :define :define_attribute
      alias :add_attribute_definition :define_attribute

      # Return the collection of attribute definitions associated with this category.
      def attribute_definitions
        query_for :attribute_definitions do
          PublicEarth::Db::Attribute.attributes_hash_from_records(PublicEarth::Db::Category.many.attribute_definitions(self.id))
        end
      end

      def attribute_definitions?
        !@attribute_definitions.nil?
      end
      
      def attribute_definitions=(value)
        assign :attribute_definitions, value
      end
      
      # This is a last-ditch effort to get the category slug.  Some older queries don't include the slug.
      def slug
        query_for :slug do
          category = PublicEarth::Db::Category.find_by_id(self.id)
          category && category.slug || self.id.underscore.gsub(/_/, '-')
        end
      end
      
      def ==(other)
        other.kind_of?(PublicEarth::Db::Category) && self.id == other.id
      end
      
      def to_s
        self.name
      end
      
      def nearby_categories
        query_for :nearby_categories do
          PublicEarth::Db::Category.many.get_nearby_categories(self.id).map{ |attributes| PublicEarth::Db::Category.new(attributes) }
        end
      end
      
      def boost
        children.present? && 2.0 || 1.0
      end

      def search_document
        {
          :id => self.id,
          :name => self.name,
          :slug => self.slug,
          :assignable => children.blank?,
          :synonym => (PublicEarth::Db::Category.many.synonyms(self.id).map {|c| c.values}).flatten + [self.name] + (self.hierarchy.map { |h| h.name })
        }
      end
      
      private
    
        def add_categories(parents)
          parents.each do |parent|
            @categories[parent['id']] = parent unless @categories[parent['id']]
            add_categories(parent['parents']) if parent['parents']
          end
        end

        def add_children(building_array, children)
          children.each do |child|
            child = @categories[child]
          
            # We need to dup the original, in case we have multiple children.  One branch per
            # set of children.
            cloned = building_array.dup
            cloned << {child['id'] => child['name']}
          
            # If this category has children, build out the full array; otherwise, we must be
            # at a leaf, so add it to our branches array.
            if child['children']
              add_children(cloned, child['children']) if child['children']
            else
              @category_branches << cloned
            end
          end
        end
    
    end
  end
end

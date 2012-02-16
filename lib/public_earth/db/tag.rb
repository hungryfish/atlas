module PublicEarth
  module Db
    
    # Tags are built off the extended_place_tag type in the database, rather than the tags
    # or place_tags tables.  The type is as follows:
    #
    #   tag_id varchar(40),
    #   place_tag_id varchar(40),
    #   name varchar(64),
    #   language varchar(8),
    #   created_at timestamp,
    #   updated_at timestamp,
    #   place_id varchar(40),
    #   source_data_set_id varchar(40)
    #
    class Tag < PublicEarth::Db::Base

      attr_accessor :attribute_definitions
    
      finder :name
      
      class << self

        # Create a new tag.  If the tag already exists, will ignore the request and return the existing tag.
        # All tags are automatically lowercased by the database.
        def create(name, language = nil)
          new(one.create(name, language) || raise(CreateFailed, "Unable to create the tag #{name}."))
        end
    
        # Create a new tag as a category.  If the tag already exists, will turn it into a category if it's
        # not one already.
        def category(name)
          new(one.create(name, true) || raise(CreateFailed, "Unable to create the category #{name}."))
        end
      
        # Delete a tag by its name.  If the tag exists, the original tag information is returned.  Otherwise
        # returns nil.
        def delete(name)
          existing_tag = one.delete(name)
          existing_tag && new(existing_tag) || nil
        end
        
      end # class << self
    
      # We need to make tag_id into id...
      def initialize(attributes = {})
        attributes[:id] = (attributes[:tag_id] || attributes['tag_id']) unless (attributes[:id] || attributes['id'])
        super(attributes)
      end
      
      # Indicate that this tag is also a category.  You could also use PublicEarth::Db::Tag.category(name).
      def is_a_category
        result = PublicEarth::Db::Tag.one.as_category(self.id)
        self.category = result['category']
        self
      end
    
      # Return the collection of places associated with this tag.  This should ONLY be used for testing,
      # as it limits the number of places returned to 10.
      def places
        PublicEarth::Db::Category.many.places(self.id, 10).map { |attributes| PublicEarth::Db::Tag.new(attributes) }
      end
    
      # Add a place to this tag, as a category.  Will convert the tag into a category if it isn't one already,
      # then add this place to it.  Requires a data set to associated with the modification.
      def add_place(place, data_set)
        PublicEarth::Db::Category.one.add_place(self.id, place.id, data_set.id)
      end
    
      # Remove a place from this category.  NEED A BETTER WAY TO DO THIS!  How do we track what user removed
      # the category?
      def remove_place(place)
        PublicEarth::Db::Category.one.remove_place(self.id, place.id)
      end
    
      # Compare the tag name.
      def <=>(other)
        self.to_s <=> other.to_s
      end
        
      # Equate on the tag name.
      def ==(other)
        other.kind_of?(Tag) && self.name == other.name
      end
      
      # Return the tag name.
      def to_s
        self.name
      end
    end
  end
end
require 'xml'
#require 'lib/atlas/history/convert'

module Atlas
  class History
    
    attr_reader :being_modified, :data_set, :logger
    
    # History files are recorded here...
    class RecentChange < PublicEarth::Db::Base
      def self.schema_name
        'history'
      end
      
      def self.all
        many.recent_changes.map {|r| new r}
      end
      
      # Record a change to the history.  Used by the History class; you shouldn't call this directly!
      def self.create(place_id, source_id, history_file)
        new one.recently_changed(place_id, history_file, source_id)
      end
      
      def self.find_all_by_place(place)
        many.find_all_by_place(place.id).map {|r| new r}
      end
      
      def self.find_all_by_place_and_source(place, source)
        many.find_all_by_place_and_source(place.id, source.id).map {|r| new r}
      end
      
      def delete
        Atlas::History::RecentChange.one.delete(self.id)
      end
    end
    
    # A simple way to generate a few history commands in a statement or two.  Supply the place
    # you're talking about and the data_set it came from, and the history will be passed to the
    # block and recorded when done.
    #
    #   History.record @place, current_user do |h|
    #     h.changed_category 'Parks', 'Trails'
    #     h.deleted_attribute 'dajf4-234utqr-2nifaew-faw32'
    #   end
    #
    # You may also just call History.record without a block, to record a single event.
    #
    #   History.record(@place, current_user).changed_category_to('Trails')
    #
    def self.record(being_modified, data_set, &block)
      if block
        history = History.new(being_modified, data_set)
        block.call(history) 
        history.record
      else
        History.new(being_modified, data_set, true)
      end
    end
    
    # Delete the history for an place and data_set.
    #
    # History.delete(@place, data_set)
    #
    def self.delete(being_modified, data_set=nil)
      if data_set
        data_set = data_set.data_set if data_set.respond_to? :data_set
        recent_changes = Atlas::History::RecentChange.find_all_by_place_and_source(being_modified, data_set.source)
      else
        recent_changes = Atlas::History::RecentChange.find_all_by_place(being_modified)
      end
      
      recent_changes.each do |rc|
        $record_keeper.delete(rc)
        rc.delete
      end
    end
    
    # Create a new History object if you need to make many changes to the history over a number
    # of methods.  Place Details uses this construct.  Using History.record will be easier in
    # most situations.
    #
    # Indicate transactionless to write every change as it occurs.  If you do not supply a value,
    # defaults to false and you must call history.record to write the changes to disk (manually).
    #
    #   @history = History.new(@place)
    #   ...
    #   @history.created_attribute('dajf4-234utqr-2nifaew-faw32', 'Open Weekends')
    #   ...
    #   @history.modified_attribute('lad2f4-23aatqp-266hdsew-ddw32', 'Open Late')
    #   ...
    #   @history.record
    #
    # The being_modified attribute indicates the object being updated.  Supports Place and Category
    # currently.
    def initialize(being_modified, data_set_ish = nil, transactionless = false)
      @logger = RAILS_DEFAULT_LOGGER
      
      # Run out of variable names here? I mean, really. (MTG)
      @data_set = data_set_ish.respond_to?(:data_set) && data_set_ish.data_set || data_set_ish
      
      @being_modified = being_modified
      
      @actions = []
      @transactionless = (!! transactionless)
      
    end
    
    # Indicate who is making this change.  You may pass in a source_data_set, or an object that
    # can supply its own source_data_set, such as a user or source.
    def data_set=(data_set_ish)
      @data_set = data_set_ish.respond_to?(:data_set) && data_set_ish.data_set || data_set_ish
    end
    
    def action(to_take)
      @actions << to_take
      record if @transactionless
      to_take
    end
    
    def created_place(place)
      logger.debug("Created place: #{place.inspect}")
      action CreatePlaceAction.new(self, place)
    end
    
    def created_attribute(attribute)
      logger.debug("Creating attribute: #{attribute.inspect}")
      action CreateAttributeAction.new(self, attribute)
    end

    def updated_attribute(attribute)
      logger.debug("Updating attribute: #{attribute.inspect}")
      action UpdateAttributeAction.new(self, attribute)
    end

    def deleted_attribute(attribute)
      logger.debug("Deleting attribute: #{attribute.inspect}")
      action DeleteAttributeAction.new(self, attribute)
    end
    
    def changed_category(new_category, original_category)
      logger.debug("Changed category from #{original_category} to #{new_category}")
      action UpdateCategoryAction.new(self, new_category, original_category)
    end

    def add_keyword(keyword)
      logger.debug("Added keyword #{keyword}")
      action AddKeywordAction.new(self, keyword)
    end

    def delete_keyword(keyword)
      logger.debug("Deleted keyword #{keyword}")
      action DeleteKeywordAction.new(self, keyword)
    end
    
    def add_photo(photo)
      logger.debug("Added photo #{photo.filename}")
      action AddPhotoAction.new(self, photo)
    end

    def repositioned(new_latitude, new_longitude, old_latitude, old_longitude)
      logger.debug("Repositioned from #{old_latitude}x#{old_longitude} to #{new_latitude}x#{new_longitude}")
      action RepositionedPlaceAction.new(self, new_latitude, new_longitude, old_latitude, old_longitude)
    end
    
    # Generate the XML to output for the history.  Requires the data_set be indicated.
    def xml
      raise "Please indicate a data set for this change." unless @data_set
      
      xml = XML::Document.new
      xml.encoding = XML::Encoding::UTF_8
      xml.root = XML::Node.new('history')
      
      # When?
      xml.root['created_at'] = Time.now.xmlschema

      # Who?
      xml.root << Convert::DataSet.to_xml(@data_set)
      
      # What?
      modified_xml = nil
      
      create_action = nil
      other_actions = []
      @actions.each do |a| 
        if a.kind_of?(Atlas::CreatePlaceAction) && a.place == @being_modified 
          create_action = a
        else
          other_actions << a
        end
      end

      if @being_modified.kind_of?(Atlas::Place) && !create_action.present?
        modified_xml = Convert::Place.to_xml(@being_modified)
      elsif @being_modified.kind_of? Atlas::Category
        modified_xml = Convert::Category.to_xml(@being_modified)
      end
      
      modified_xml = create_action.record if create_action.present?
      
      # How?
      other_actions.each { |action| modified_xml << action.record }
      
      xml.root << modified_xml

      xml
    end
    
    # Record the changes to disk and wipe the history cache.  Also clears out the actions once 
    # they have been recorded, so you can reuse the object.
    #
    # In most instances the data_set value on the history object must be set.
    #
    # Uses the $record_keeper global variable to output to the desired source, be it a file 
    # system, S3, syslog, or whatever.  Defaults to just logging the XML to the default database
    # logger.
    def record
      unless @actions.empty?
        $record_keeper && $record_keeper.output(self) || ActiveRecord::Base.logger.info("This is an historic event!\n#{xml}")
        @actions.clear
      end
    end
    
  end # class History

  # The base class of all the actions related to attributes.
  class AttributeAction
    extend ActiveSupport::Memoizable
    
    def initialize(history, attribute)
      @history = history
      @attribute = attribute
      
      self.record
    end
  end # class AttributeAction
  
  # A new attribute has been associated with a place.
  class CreateAttributeAction < AttributeAction
    def record
      xml = XML::Node.new('attribute')
      xml['action'] = 'created'
      
      created = XML::Node.new('created')
      created << Atlas::History::Convert::Attribute.to_xml(@attribute)
      xml << created
      
      xml
    end
    memoize :record
  end # class CreateAttributeAction

  # A attribute has been updated for a place.
  class UpdateAttributeAction < AttributeAction
    def record
      xml = XML::Node.new('attribute')
      xml['action'] = 'updated'
      
      updated = XML::Node.new('updated')
      updated << Atlas::History::Convert::Attribute.to_xml(@attribute, :include => :original)
      xml << updated
      
      xml
    end
    memoize :record    
  end # class UpdateAttributeAction

  # A attribute has been deleted from a place.
  class DeleteAttributeAction < AttributeAction
    def record
      xml = XML::Node.new('attribute')
      xml['action'] = 'deleted'
      
      deleted = XML::Node.new('deleted')
      deleted << Atlas::History::Convert::Attribute.to_xml(@attribute, :include => :original)
      xml << deleted
      
      xml
    end
    memoize :record    
  end # class DeleteAttributeAction
  
  # The base class of all the actions related to categories.
  class CategoryAction
    def initialize(history, new_category, original_category = nil)
      @history = history
      @new_category = new_category
      @original_category = original_category
    end
  end # class CategoryAction
  
  # Create a category, or if the category tag is inside a place tag, initially attach the
  # place to a category.
  class CreateCategoryAction < CategoryAction
    def record
      xml = XML::Node.new('category')
      xml['action'] = 'created'

      created = XML::Node.new('created')
      created << Atlas::History::Convert::Category.to_xml(@new_category)
      xml << created
      
      xml
    end
  end # class CreateCategoryAction
  
  # Modify a category, or if the category tag is inside a place tag, change the category a 
  # place is in.
  class UpdateCategoryAction < CategoryAction
    def record
      xml = XML::Node.new('category')
      xml['action'] = 'updated'

      updated = XML::Node.new('updated')
      updated << Atlas::History::Convert::Category.to_xml(@new_category)
      xml << updated
      
      original = XML::Node.new('original')
      original << Atlas::History::Convert::Category.to_xml(@original_category)
      xml << original

      xml
    end
  end # class UpdateCategoryAction

  # The place has moved.  Right now, does not handle changing regions or routes.
  class RepositionedPlaceAction
    def initialize(history, new_latitude, new_longitude, old_latitude, old_longitude)
      @history = history
      @new_latitude = new_latitude
      @new_longitude = new_longitude
      @old_latitude = old_latitude
      @old_longitude = old_longitude
    end
    
    def record
      xml = XML::Node.new('repositioned')

      updated = XML::Node.new('updated')
      updated << XML::Node.new('latitude', @new_latitude.to_s)
      updated << XML::Node.new('longitude', @new_longitude.to_s)
      xml << updated

      if (@old_latitude && @old_longitude)
        original = XML::Node.new('original')
        original << XML::Node.new('latitude', @old_latitude.to_s)
        original << XML::Node.new('longitude', @old_longitude.to_s)
        xml << original
      end
      
      xml
    end
  end # class RepositionedPlaceAction
  
  # The base class of all the actions related to categories.
  class KeywordAction
    def initialize(history, keyword)
      @history = history
      @keyword = keyword
    end
  end # class KeywordAction
  
  # Add a keyword to a place.
  class AddKeywordAction < KeywordAction
    def record
      xml = XML::Node.new('keyword')
      xml['action'] = 'add'
      xml << @keyword
      
      xml
    end
  end # class AddKeywordAction
  
  # Remove a keyword from a place.
  class DeleteKeywordAction < KeywordAction
    def record
      xml = XML::Node.new('keyword')
      xml['action'] = 'delete'
      xml << @keyword
      
      xml
    end
  end # class RemoveKeywordAction
  
  # The base class of all the actions related to photos.
  class PhotoAction
    def initialize(history, photo)
      @history = history
      @photo = photo
    end
  end # class PhotoAction
  
  # Add a photo to a place.
  class AddPhotoAction < PhotoAction
    def record
      xml = XML::Node.new('photo')
      xml['action'] = 'add'
      xml << @photo.attributes[:filename]
      xml
    end
  end # class AddPhotoAction
  
  class PlaceAction
    def initialize(history, place)
      @history = history
      @place = place
    end
    
    attr_reader :place
  end
  class CreatePlaceAction < PlaceAction
    def record
      Atlas::History::Convert::Place.to_xml(@place, :new_record => true)
    end
  end 
end

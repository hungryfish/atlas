module Atlas
  class PlaceAttribute < ActiveRecord::Base
    include Enumerable 
    
    attr_accessor :priority, :details 
    
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :definition, :class_name => 'Atlas::AttributeDefinition', :foreign_key => 'attribute_definition', :primary_key => 'name'
    has_many :values, :class_name => 'Atlas::PlaceValue', :dependent => :destroy, :autosave => true

    before_update :record_change
    before_destroy :record_delete
    before_create :record_create
    
    def record_delete
      details.place.history.deleted_attribute(self)
    end
    
    def record_create      
      details.place.history.created_attribute(self) unless self.values.blank?
    end
    
    def record_change
      unless self.values.blank?
        
        self.values.each do |v|
          if v.new_record?
            logger.debug(">>>>> #{self.attribute_definition} value #{v.value} was created")
            details.place.history.created_attribute(self)
          elsif v.marked_for_destruction?
            logger.debug(">>>>> #{self.attribute_definition} value #{v.value} was destroyed.")
            details.place.history.deleted_attribute(self)
          elsif v.changed?
            logger.debug(">>>>> #{self.attribute_definition} changed from #{v.value_was} to #{v.value}")
            details.place.history.updated_attribute(self)
          end
        end
        
      end
    end
    
    # TODO:  HANDLE BLANK STRINGS!!!
    
    # Reset the value to the given value or values.  
    def set(value)
      return if value.nil?
      value = value.value if value.kind_of? Atlas::PlaceValue
      source_data_set_id = current_source_data_set ? current_source_data_set.id : nil
      
      # Handle resetting an array of values
      if value.kind_of? Array
        to_set = value.dup.map {|s| s.to_s}
        values.each do |place_value|
          unless to_set.include?(place_value.value)
            place_value.mark_for_destruction
          else
            to_set.delete(place_value.value)
          end
        end
        to_set.each do |s|
          values.build(:value => s, :source_data_set_id => source_data_set_id) if s.present?
        end
        
      # Handle a single value, e.g. place.details.name = "Bob's Big Boy"
      else
        value = value.present? && value.to_s || nil
        
        # Are we resetting a single value?  Then just update its value and source data set.
        if values.length == 1 && values.first.value != value && value.present?
          values.first.value = value
          values.first.source_data_set_id = source_data_set_id
          
        # Otherwise set every other place in the array for deletion.
        else
          found = false
          values.each do |place_value|
            if place_value.value != value
              place_value.mark_for_destruction
            else
              found = true
            end
          end
          values.build(:value => value, :source_data_set_id => source_data_set_id) if !found && value.present?
        end
      end
    end
    
    # Add a value to the array of values for this attribute.  If the value already exists, the request is ignored.
    def add(value)
      return if value.nil?
      source_data_set_id = current_source_data_set.id
      value = value.value if value.kind_of? Atlas::PlaceValue
      if value.kind_of? Array
        value.each {|v| add(v, source_data_set_id)}
      else
        values.build(:value => value.to_s, :source_data_set_id => source_data_set_id) unless values.map(&:value).include?(value.to_s) || value.to_s.blank?
      end
    end
    alias :<< :add
   
    # Treats the values associated with this attribute like an array of strings.  To get the PlaceValue objects,
    # call something like place.details.useful_links.values.
    def each 
      values.each { |value| yield value.to_s }
    end
    
    def first
      values.first
    end
    
    def last
      values.last
    end
    
    def present?
      values.present?
    end
    
    def blank?
      values.blank?
    end
    
    # Same as calling values.length; just so attributes appear to be an array, falling off details, e.g.
    # place.details.useful_links.length.
    def length
      values.length
    end
    alias :size :length
    
    # Return the first PlaceValue's value for this attribute.  This works in about 80% of the cases, such as
    # name, description, street, city, state_province, etc.
    def to_s
      values.first.to_s
    end
    
    private
    
      # From the details manager...
      # If there's no source_data_set, mark the record as readonly.
      def current_source_data_set
        if details && details.source_data_set
          details.source_data_set
        else
          self.readonly!
          nil
        end
      end

  end
end
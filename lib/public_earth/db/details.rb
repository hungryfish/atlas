module PublicEarth
  module Db

    # Handles details about a place.  This is not a data model, nor does it have any associated
    # tables or functions.  It is a wrapper for place, attribute_definitions, and 
    # place_attribute_values functionality.
    #
    # Allows you to refer to place attributes directly, e.g. place.details.name.  Also supports
    # language:  place.details.name('Rucksack', 'de').  Finally, tracks the source of the 
    # information, using the source() method, similar to a transaction.
    #
    # Details does an incredible amount of work to maintain proper state of place attribute
    # values to efficiently save them.  Don't forget to call the save method when you're done
    # editing the details.
    #
    # Attributes with many values have been added.  If an attribute definition indicates that
    # the attribute supports allow_many, the attribute value is treated with a special object
    # mimicing an Array.  This manages the different attribute values while allowing you to 
    # interact with them like a simple Array of Strings or Fixnums.
    class Details
      include Enumerable
      include PublicEarth::Xml::Helper
      
      DEFAULT_LANGUAGE = 'en'

      attr_accessor :current_language, :current_source_data_set, :history, :read_only
      
      # These should only be used in a read-only capacity.  If you modify the position of the
      # place, it will not be reflected here until the place is reloaded!  
      attr_reader :latitude, :longitude

      # Manages a single place attribute value, along with its definition.  For attributes with many
      # values, this class stores the individual values, while ManyValues tracks the collection of
      # them for a single attribute name.
      class Attribute
        attr_accessor :id, :name, :value, :comments, :language, :source_data_set_id, :definition_id, 
            :priority, :local, :required, :data_type, :allow_many, :original_value, :original_comments, 
            :readonly, :details
        
        def initialize(details, id, name, value, comments, language, source_data_set_id, readonly=false, 
              priority = 9999, local = false, required = false, allow_many = true, data_type = 'string')
          self.details = details || raise("You must attach an attribute to its details!")
          self.id = id
          self.name = name && name.to_s || raise("Invalid attribute name; may not be nil.")
          self.value = self.original_value = value
          self.comments = self.original_comments = comments
          self.data_type = data_type
          self.language = language
          self.source_data_set_id = source_data_set_id
          self.readonly = readonly
          self.priority = priority.nil? && 9999 || priority.to_i
          self.local = local
          self.required = required
          self.allow_many = allow_many
        end
      
        def +(value)
          unless value.blank?
            self.changed = true
            self.value += value
          end
        end
        alias :<< :+

        # Compare the attribute name.
        def <=>(other)
          self.name <=> other.name
        end
        
        # If comparing an attribute, looks to see if both the name and value match.  If comparing any other
        # value, looks to see if the attribute value matches.
        def ==(other)
          if other.kind_of? Details::Attribute
            self.name == other.name && self.value == other.value
          else
            self.value == other
          end
        end
        
        # Create, update or delete this attribute in the database.  Don't call this directly; the save()
        # method on details will handle everything for you.
        def save(place, history)
          results = nil
          if deleted?
            results = PublicEarth::Db::Place.one.remove_attribute_value(id, source_data_set_id) unless id.nil?
            history.deleted_attribute(self)
          elsif changed? 
            if exists?
              if (self.value != self.original_value || self.comments != self.original_comments)
                results = PublicEarth::Db::Place.one.update_attribute_value(self.id, value, comments, source_data_set_id)
                history.updated_attribute(self)
              end
            else
              results = PublicEarth::Db::Place.one.set_attribute_value(place.id, name, value, language, comments, 
                  source_data_set_id)
              self.id = results['id']
              history.created_attribute(self) # We want the ID, but not the exists!
              self.exists = true
            end
          end
          self.changed = false
          results
        end
        
        # If you change a deleted attribute, it will "come back to life", i.e. deleted is set to false.
        def changed=(value)
          @changed = value
          @deleted = false if value == true
        end
      
        # Has this attribute been changed from its original value?
        def changed? 
          @changed == true
        end
      
        # Sets the deleted flag.  
        def deleted=(value)
          @deleted = value
        end
      
        # Has this attribute been deleted?
        def deleted?
          @deleted == true
        end
      
        # Indicate whether or not this value already exists in the database.
        def exists=(value)
          @exists = value
        end
      
        # Does this value exist in the database, i.e. it's not new?
        def exists?
          @exists == true
        end
      
        # Is this attribute attached directly to a Place or the category the
        # place is in? (if not, its considered 'common' and not local)
        def local?
          @local == true
        end
        alias :is_local? :local?
        
        def local=(value)
          @local = value
        end

        # Is a value required for this attribute for the place to be saved?
        def required?
          @required == true
        end
        alias :is_required? :required?
        
        def required=(value)
          @required = value
        end
        
        # Support multiple values for this attribute?
        def allow_many?
          @allow_many == true
        end
        
        def allow_many=(value)
          @allow_many = value
        end
        
        # Returns true if the value has been unset or the attribute has been marked for deletion.
        def blank?
          self.value.blank? || self.deleted?
        end
        
        alias :readonly? :readonly
        
        def to_s
          self.value || ''
        end
        
        def eql?(other)
          self.id == other.id && self.value == other.value
        end
        
        def chars
          self.to_s.chars
        end
        
        def formatted
          details.apply_formatting(to_s)
        end
      end # class Attribute
      
      # Manages attributes flagged with allow_many, similar to an array, but with some functionality
      # around returning valid attribute information, such as required? and allow_many?.  Also stores
      # deleted attribute values for update to the database when saved, but does not return them by
      # default in each and map calls.
      class ManyValues
        include Enumerable

        # Initialize with the details object contain this one, and one of our attribute types.
        def initialize(details, attribute)
          @details = details
          @attribute = attribute
          @values = []
        end
        
        # Duplicate this object, including its values.
        def dup
          duplicate = ManyValues.new(@details, @attribute)
          duplicate.values = self.values.map { |v| v.dup }
          duplicate
        end
        
        # Returns the attribute name associated with this model.
        def name
          @attribute.name
        end

        # Return the definition ID of this attribute.
        def definition_id
          @attribute.definition_id
        end
        
        def data_type
          @attribute.data_type
        end
        
        def readonly?
          @attribute.readonly
        end
        alias :readonly :readonly?

        # Return all the values for this attribute, excluding those marked as deleted.  Indicate
        # true for the include_deleted parameter to include the places marked as deleted.
        def values(include_deleted = false)
          include_deleted && @values || (@values.select { |v| !v.deleted? })
        end
        alias :to_a :values
        
        # Used to dup the collection.  You shouldn't use this outside this class.
        def values=(collection)
          @values = collection
        end
        
        # Spits back the values as an array of basic values, mostly useful for search indexes.  
        def value
          values.map { |v| v.value }
        end
        
        # Returns the number of attributes with values.  Excludes any that have been deleted but 
        # not yet saved.  If you pass in true for include_deleted, returns the length of all the
        # attributes, including the deleted ones that have not yet been saved.
        def length(include_deleted = false)
          values(include_deleted).length
        end
        
        def empty?(include_deleted = false)
          values(include_deleted).empty?
        end
        
        # Return the value at the given index.  This index goes against the entire cache, not just
        # values that haven't been deleted.  You could have a deleted value come back!
        def [](index)
          @values[index]
        end
        
        # Works on all values, not just ones that haven't been deleted.  Returns the first value stored.
        def first
          @values.first
        end
        
        # Works on all values, not just ones that haven't been deleted.  Returns the last value stored.
        def last
          @values.last
        end
        
        # Works on all values, not just ones that haven't been deleted.  Returns all values but the 
        # first value stored.
        def rest
          @values.rest
        end
        
        # Retrieve the attribute value specifically for the given value.  May return deleted attributes
        # as well.
        def get(value)
          if value.kind_of? Details::Attribute
            raise "Invalid attribute!  Must be an attribute named #{self.name}" if value.name != self.name
            value = value.value
          end
          value.strip! if value.kind_of? String
          @values.find { |v| v.value == value }
        end
        
        # Append an attribute value to an attribute that accepts multiple values.  The []= method will
        # call this method as well to handle these flagged attributes.
        #
        # Accepts either an Attribute object or a standard String, Fixnum, or other base value.  Also 
        # takes an Array of values, e.g.
        #
        #   place.details.features << ['dog', 'cat']
        #
        # You may also send comments for an attribute along with its value.  This won't work with <<, so
        # use add:
        #
        #   place.details.features.add 'dog', :comment => 'A puppy named Marley'
        #
        # Another option is to pass along the source_data_set ID directly.  This is primarily used by the
        # Details load methods:
        #
        #   place.details.features.add 'dog', :data_set_id => 'adsf-23kfsdf-23rfaef-23kleaw'
        #
        # Otherwise the current data set ID associated with the Details object that owns this will be
        # used.  It will raise an exception if you haven't indicated a source data set, using Details.from.
        def add(value, *additional)
          return if value.blank?
          
          # Pull off our options hash, for :comments and :data_set_id
          options = additional.last.kind_of?(Hash) && additional.last || {}
          
          data_set_id = options[:data_set_id] || 
              (value.kind_of?(Details::Attribute) && value.source_data_set_id) ||
              (@details.current_source_data_set && @details.current_source_data_set.id) ||
                raise("Please set the source data set before attempting to set values.")
          attribute_id = (value.kind_of?(Details::Attribute) && value.id) || nil
          
          if value.kind_of?(Array) || value.kind_of?(ManyValues)
            value.map { |v| v.kind_of?(Hash) && self.add(v[:value], :comments => v[:comments]) || self.add(v) }
          
          else
            # Is there an existing value in our ManyValues array that matches this one?
            look_for = value
          
            if value.kind_of? Details::Attribute
              raise "Invalid attribute!  Must be an attribute named #{self.name}" if value.name != self.name
              return if value.deleted?
              look_for = value.value
              options[:comments] ||= value.comments
            end
          
            look_for.strip!
            
            comments = options[:comments]
            
            existing = @values.find { |v| v.value == look_for }
            unless existing
              existing = PublicEarth::Db::Details::Attribute.new(self, attribute_id, 
                  @attribute.name, look_for, comments, @attribute.language, data_set_id, @attribute.readonly,
                  @attribute.priority, @attribute.local, @attribute.required, true, @attribute.data_type)
              @values << existing
            else
              existing.comments = comments unless comments.nil?
            end

            # Bring in the existing attribute state, if we passed in a full attribute object.
            if value.kind_of?(Details::Attribute)
              existing.exists = value.exists?
              existing.deleted = value.deleted?
              existing.changed = value.changed?
            else
              existing.changed = true
            end
            
            existing
          end
        end
        alias :<< :add
        
        # Returns a duplicate ManyValues object with the value appended.  Does not affect the existing 
        # value.  In all other ways, works like <<.
        def +(value)
          duplicate = self.dup 
          duplicate << value
          duplicate
        end
        
        # Remove a value from the collection by subtracting it:
        #
        #   place.details >> "Boat Dock"
        #
        # subtracting multiple values is also supported:
        #
        #   place.details >> ["Boat Dock", "Fishing Spot"]
        def >>(value)
          return if value.blank?
          raise "Please set the source data set before attempting to set values." unless @details.current_source_data_set
          
          unless value.kind_of? Array
            look_for = value
          
            if value.kind_of? Details::Attribute
              raise "Invalid attribute!  Must be an attribute named #{self.name}" if value.name != self.name
              return if value.deleted?
              look_for = value.value
            end
            
            existing = @values.find { |v| v.value == look_for }
            existing.deleted = true if existing
            existing
          else
            value.map do |v|
              self >> v
            end
          end
        end
        
        # This returns a duplicate ManyValues object with the given values removed.  Any values that didn't
        # exist in the first place are ignored.  It does not affect the existing value stored on the attribute,
        # but in all other ways works like >>.
        def -(value)
          duplicate = self.dup 
          duplicate >> value
          duplicate
        end
        
        # Set all values to the deleted state.
        def clear
          @values.each { |v| v.deleted = true }
        end
        
        # Cycle through and create, update, or delete all the attribute values.
        def save(place, history)
          @values.each { |v| v.save(place, history) }
        end
        
        def required?
          @attribute.required?
        end
        
        # Always true.
        def allow_many?
          true
        end
        
        # Does any definition in this multivalue attribute have its changed? or deleted? flags set?
        def changed? 
          @values.any { |v| v.changed? || v.deleted? }
        end
      
        # Has this attribute been emptied?
        def deleted?
          values.length == 0 && values(true).length > 0
        end
      
        # Do any entries for this attribute existing in the database already?
        def exists?
          @values.any { |v| v.exists? }
        end
      
        # Is this attribute attached directly to a Place or the category the
        # place is in? (if not, its considered 'common' and not local)
        def local?
          @attribute.local?
        end
        alias :is_local? :local?
        
        def priority
          @attribute.priority
        end
        
        # Excludes any attributes that have been deleted by default.  If you'd like to include those,
        # pass in true for include_deleted.
        def each(include_deleted = false)
          values(include_deleted).each do |v|
            yield v
          end
        end
        
        # Sorts against other ManyValues objects and Attribute objects.
        def <=>(other)
          self.name <=> other.name
        end
        
        def to_s
          map(&:to_s).join(', ')
        end
        
        def formatted
          (map { |attr| @details.apply_formatting(attr.to_s) }).join(', ')
        end
        
        # Spits out an array.
        def to_plist
          node = XML::Node.new('array')
          values.each do |attribute|
            node << attribute.to_s.to_plist
          end
          node
        end
        
      end  # class ManyValues
    
      def self.logger
        ActiveRecord::Base.logger
      end
      
      # ===== Start Details instance methods... =====
      
      # Initialize the place details.  If you loaded the place and attributes together, pass the mixed 
      # database results into the end.
      def initialize(place, category_id = nil, language = nil, mixed_records = nil)
        @place = place
        @category_id = category_id
        @current_language = language || DEFAULT_LANGUAGE
        @history = History.new(@place)
        mixed_records && self.load_mixed(mixed_records) || self.load
        
        @latitude = place.latitude
        @longitude = place.longitude
      end
    
      def logger
        Details.logger
      end
      
      # Set the current language for the incoming data.  After calling this method, any attribute
      # values set will be associated with the given language code.  If you change the code, the
      # previously set attributes will stay associated with the old language value, but newer 
      # attributes will be set to the current language code.
      def language(code = nil)
        @current_language = code || DEFAULT_LANGUAGE
        @attributes[@current_language] ||= {}
      end
      alias :language= :language
    
      # Indicate the session ID for this data set, for use in tracking the data set.
      def session(session_id)
        @session_id = session_id
      end
      alias :session= :session
    
      # Set who is responsible for this information.  If you pass in a user object, that user's
      # source data set is used (a shortcut).  You can also pass in a source data set ID, rather
      # than an entire source data set object.  
      #
      # The source data set information is attached to each value.  If you change the from value,
      # any existing values remain with the previous values, but those attributes set now and in
      # the future are attached to this data set.
      def from(source_data_set)
        if source_data_set.respond_to? :source_data_set
          source_data_set = source_data_set.source_data_set
        elsif source_data_set.kind_of? String
          source_data_set = PublicEarth::Db::DataSet.find_by_id!(source_data_set)
        end
        @history.data_set = @current_source_data_set = source_data_set
      end
      alias :from= :from
    
      # Save the details to the database.  Rather than saving them individually, this will be
      # a bit more efficient, even though it requires an extra step.  Attribute values are cached
      # in memory until saved.
      def save(options = {})
        options.stringify_keys!
        contribute = options.delete('contribute') || true
        
        @attributes.each do |language, language_attributes_hash|
          language_attributes_hash.each do |attribute_name, attribute|
            attribute.save(@place, @history)
          end
        end

        PublicEarth::Db::Contributor.contribute(@place, @current_source_data_set) if contribute
        
        @history.record
        
        @attributes
      end
 
      # Load any existing values from the database.  This will clear out any current, unsaved 
      # values, so make sure you either save or you want the values to be cleared.
      def load
        # Reload the name, if needs be...
        @place.name = nil
        
        @attributes = Hash.new { |hash, key| hash[key] = {} }
        @attributes[@current_language] ||= {}
      
        PublicEarth::Db::Place::many.attributes(@place.id, @current_language).each do |attribute_value|
          @attributes[attribute_value['language']] ||= {}

          attribute_definition = PublicEarth::Db::Details::Attribute.new(
              self, 
              attribute_value['id'],
              attribute_value['attribute_definition_name'],
              attribute_value['value'],
              attribute_value['comments'],
              attribute_value['language'],
              attribute_value['source_data_set_id'],
              attribute_value['attribute_is_readonly'] == 't',
              attribute_value['priority'],
              attribute_value['is_local'] == 't',
              attribute_value['is_required'] == 't',
              attribute_value['allow_many'] == 't',
              attribute_value['attribute_definition_type']
            )

          # Since we're getting all the possible attributes, whether or not they have values yet, we 
          # need to test to make sure it doesn't exist, i.e. the value from the database should be NULL.
          attribute_definition.exists = true unless attribute_value['value'].blank?

          # Is this a many values attribute? 
          if attribute_value['allow_many'] == 't'
            @attributes[attribute_value['language']][attribute_value['attribute_definition_name'].to_sym] ||= 
                ManyValues.new(self, attribute_definition)

            @attributes[attribute_value['language']][attribute_value['attribute_definition_name'].to_sym] << 
                attribute_definition
          else
            @attributes[attribute_value['language']][attribute_value['attribute_definition_name'].to_sym] = 
                attribute_definition
          end
        end
        @attributes
      end

      # Load any existing values from the database.  This will clear out any current, unsaved 
      # values, so make sure you either save or you want the values to be cleared.
      #
      # This will load the attributes from a joint place/attributes database call, where the place
      # information and attributes information is mixed in together for a more efficient, single 
      # request.  See the stored procedure place.all_with_attributes() and place.next_with_attributes()
      # for examples, along with place.each_with_details(), which uses this method.
      #
      # Pass in the array of results you received from the database.
      def load_mixed(mixed_results)
        # Reload the name, if needs be...
        @place.name = nil

        @attributes = Hash.new { |hash, key| hash[key] = {} }
        @attributes[@current_language] ||= {}
      
        mixed_results.each do |attribute_value|
          @attributes[attribute_value['attribute_language']] ||= {}

          unless attribute_value['attribute_source_data_set_id']
            a = PublicEarth::Db::Attribute.find_by_name(attribute_value['attribute_definition_name'])
            if a
              attribute_value['attribute_is_readonly'] = a.readonly
              attribute_value['attribute_allow_many'] = a.allow_many
              attribute_value['attribute_source_data_set_id'] = 'READ_ONLY'
              attribute_value['attribute_definition_type'] = a.data_type
            end
          end
          
          attribute_definition = PublicEarth::Db::Details::Attribute.new(
              self,
              attribute_value['attribute_value_id'],
              attribute_value['attribute_definition_name'],
              attribute_value['attribute_value'],
              attribute_value['attribute_comments'],
              attribute_value['attribute_language'],
              attribute_value['attribute_source_data_set_id'],
              attribute_value['attribute_is_readonly'] == 't',
              attribute_value['attribute_priority'],
              attribute_value['attribute_is_local'] == 't',
              attribute_value['attribute_is_required'] == 't',
              attribute_value['attribute_allow_many'] == 't',
              attribute_value['attribute_definition_type']              
            )

          # Since we're getting all the possible attributes, whether or not they have values yet, we 
          # need to test to make sure it doesn't exist, i.e. the value from the database should be NULL.
          attribute_definition.exists = true unless attribute_value['attribute_value'].blank?

          # Is this a many values attribute?
          if attribute_value['attribute_allow_many'] == 't'
            @attributes[attribute_value['attribute_language']][attribute_value['attribute_definition_name'].to_sym] ||= 
                ManyValues.new(self, attribute_definition)
            @attributes[attribute_value['attribute_language']][attribute_value['attribute_definition_name'].to_sym] << 
                attribute_definition
          else
            @attributes[attribute_value['attribute_language']][attribute_value['attribute_definition_name'].to_sym] = 
                attribute_definition
          end
        end
        @attributes
      end
    
      # Set an attribute directly.
      def []=(attribute_name, value = nil)
        raise "Please set the source data set before attempting to set values." unless @current_source_data_set
      
        attribute_name = attribute_name.to_sym
        value.strip! if value.kind_of? String
        
        # Are we updating an existing value?
        existing = @attributes[@current_language][attribute_name] || 
            @attributes[@current_language][attribute_name.to_s.singularize.to_sym]
            
        if existing

          # An attribute that allows multiple values?
          if existing.kind_of? ManyValues
            # Always clear attribute values before re-adding them
            # That way we add new but remove values.
            existing.clear
            unless value.blank?
              value.split(',').each {|v| existing.add(v)}
            end
          # Single value attribute
          elsif existing.value != value
            existing.source_data_set_id = @current_source_data_set.id

            unless value.blank?
              existing.value = value
              existing.changed = true
            else
              existing.value = nil
              existing.deleted = true
            end
          end

        elsif !value.blank?
          
          # Look up the attribute to get its details:  required, allow_many, data_type.
          attribute_definition = PublicEarth::Db::Attribute.find_by_name(attribute_name.to_s) ||
            PublicEarth::Db::Attribute.find_by_name!(attribute_name.to_s.singularize)
          
          # If the attribute allows many values, we need an array.
          if attribute_definition.allow_many?
            @attributes[@current_language][attribute_name] ||= ManyValues.new(self, 
                PublicEarth::Db::Details::Attribute.new(self, nil, 
                attribute_name, value.split(','), nil, @current_language, @current_source_data_set.id, attribute_definition.readonly, 9999, false, 
                false, attribute_definition.allow_many, attribute_definition.data_type))
            return @attributes[@current_language][attribute_name].add(value)
            
          # Otherwise just set the attribute equal to the new value
          else
            @attributes[@current_language][attribute_name] = PublicEarth::Db::Details::Attribute.new(self, nil, 
                attribute_name, value, nil, @current_language, @current_source_data_set.id, attribute_definition.readonly, 9999, false, 
                false, attribute_definition.allow_many, attribute_definition.data_type)
            @attributes[@current_language][attribute_name].changed = true
          end
        end
      end

      # Return the attribute of the given name.
      def [](attribute_name)
        @attributes[@current_language][attribute_name.to_sym] || 
            @attributes[@current_language][attribute_name.to_s.singularize.to_sym]
      end
    
      # Wipe out any existing attributes without saving them.
      def clear
        @attributes = Hash.new { |hash, key| hash[key] = {} }
      end
    
      # Return all the attribute values associated with this place, by language.  Defaults to
      # English.
      def values(language = DEFAULT_LANGUAGE)
        @attributes[language].values.map {|attribute| attribute.value}
      end
      
      def each
        values = @attributes[@current_language] && @attributes[@current_language].values || []
        values.sort! { |a, b| a.priority <=> b.priority }
        values.each { |value| yield value }
      end
      
      def <=>(other)
        @attributes[@current_language] <=> other.attributes[@current_language]
      end
      
      def attributes
        @attributes[@current_language]
      end
      
      # Similar to calling attributes to get all the attributes in the current langauge, this 
      # method accepts a single symbol or array of symbols of what attributes to exclude.  
      # Helpful if you want to handle one or two attributes in a special way.
      def except(attributes_to_exclude)
        attributes_to_exclude = [attributes_to_exclude] unless attributes_to_exclude.kind_of? Array
        attributes_to_exclude.map! { |a| a.to_s.singularize }
        attributes.select { |a| !attributes_to_exclude.include?(a.id) }
      end
      
      # Render the given wiki formatted value as HTML, via the RedCloth wiki formatter.
      def wiki_as_html(wiki_value)
         RedCloth.new("#{wiki_value}", [:filter_html, :filter_styles, :filter_ids, :filter_classes, :no_span_caps]).to_html
      end
      
      # Render the given wiki formatted value as text, with the wiki formatting stripped out.
      def wiki_as_text(wiki_value)
        RedCloth.new("#{wiki_value}", [:filter_html, :filter_styles, :filter_ids, :filter_classes, :no_span_caps]).to(RedCloth::Formatters::Text)
      end
      
      # Take a format type -- :raw, :html, or :text -- and render the value using the proper filter.
      def apply_formatting(value, format = @place.content_format)
        case (format || :raw).to_sym
        when :html
          wiki_as_html(value)
        when :text
          wiki_as_text(value)
        else
          value
        end
      end
      
      # Generate a hash of attributes and values for the place details.  By default, raw values are
      # returned, i.e. wiki formatting, etc.  Set format = :html to generate HTML from the wiki fields,
      # or format = :text to extract the text without the wiki formatting.
      def to_hash(options = {})
        attributes_hash = {}
        self.each do |attribute|
          
          if(attribute.name == "description" && !attribute.value.blank?)
            summary = RedCloth.new(attribute.value).to(RedCloth::Formatters::Summary)
            attributes_hash['summary'] = summary
          end
          
          if options[:include_comments]
            if attribute.allow_many?
              attributes_hash[attribute.name] = attribute.values.map { |a| { :value => apply_formatting(a.value), :comments => a.comments } }
            else
              attributes_hash[attribute.name] = { :value => apply_formatting(attribute.value), :comments => attribute.comments }
            end
          else
            if attribute.allow_many?
              attributes_hash[attribute.name] = attribute.values.map { |a| apply_formatting(a.value) }
            else
              attributes_hash[attribute.name] = apply_formatting(attribute.value)
            end
          end
        end
        attributes_hash
      end
      
      # Create a libxml XML::Node representing these details.  By default, raw values are
      # returned, i.e. wiki formatting, etc.  Set format = :html to generate HTML from the wiki fields,
      # or format = :text to extract the text without the wiki formatting.
      def to_xml
        xml = XML::Node.new('details')
        xml.lang = @current_language

        self.each do |attribute|
          if(attribute.name == "description" && !attribute.value.blank?)
            summary = RedCloth.new(attribute.value, [:filter_html, :filter_styles, :filter_ids, :filter_classes]).to(RedCloth::Formatters::Summary)
            xml << xml_value(:summary, apply_formatting(summary))
          end

          if attribute.allow_many?
            array_node = XML::Node.new(attribute.name.pluralize)
            attribute.values.each do |a|
              map = XML::Node.new(attribute.name)
              map << xml_value('value', a.value)
              map << xml_value('comments', a.comments)
              array_node << map
            end
            xml << array_node
          else
            attribute_node = XML::Node.new(attribute.name)
            attribute_node << xml_value('value', attribute.value)
            attribute_node << xml_value('comments', attribute.comments)
          end
        end
        
        xml
      end
      
      def to_json(*a)
        to_hash.to_json
      end

      # Take methods requested here and convert them to attribute values.  
      #
      # To set an attribute value:  attribute_name=(value)
      # To retrieve a value:  attribute_name
      alias :default_method_missing :method_missing
      def method_missing(method_name, *args)
        if respond_to?(method_name)
          send(method_name, *args)
        else
          default_method_missing(method_name, *args)
        end
      end
      
      # Interrupt the respond_to? call so we can trap for attributes.
      alias :base_respond_to? :respond_to?
      def respond_to?(method_name)
        define_attribute_method(method_name) unless base_respond_to?(method_name)
        base_respond_to?(method_name)
      end
      
      # Generates a method based on an attribute, if the attribute exists.
      def define_attribute_method(method_name)
        attribute_name = method_name.to_s.gsub(/([=\?]?)$/, '')
        modifier = $1
        
        attribute = PublicEarth::Db::Attribute.find_by_name(attribute_name) || 
            PublicEarth::Db::Attribute.find_by_name!(attribute_name.singularize)

        singular = attribute.name.singularize
        plural = attribute.name.pluralize

        # logger.debug "Generating methods for #{attribute}"
        
        unless base_respond_to? singular
          # logger.debug "Generating #{singular} method"
          instance_eval <<-DEFINE_METHODS
            def #{singular}(language = @current_language)
              @attributes[language.to_s][:#{attribute.name}]
            end
          DEFINE_METHODS
        end
        
        unless base_respond_to?(plural) 
          if !attribute.allow_many?
            # logger.debug "Aliasing #{plural} method to #{singular} method"
            instance_eval <<-DEFINE_ALIAS
              alias :#{plural} :#{singular}
            DEFINE_ALIAS
          else
            # logger.debug "Generating #{plural} method"
            instance_eval <<-DEFINE_METHODS
              def #{plural}(language = @current_language)
                @attributes[language.to_s][:#{singular}] ||= ManyValues.new(self,
                    PublicEarth::Db::Details::Attribute.new(self, nil, 
                    '#{singular}', nil, nil, @current_language, 
                    (@current_source_data_set && @current_source_data_set.id || nil), #{attribute.readonly == 't'}, 9999, false, 
                    false, #{attribute.allow_many == 't'}, '#{attribute.data_type}'))
              end
            DEFINE_METHODS
          end
        end

        unless base_respond_to? "#{singular}="
          # logger.debug "Generating #{singular}= method"
          instance_eval <<-DEFINE_METHODS
            def #{singular}=(value)
              self['#{singular}'] = value
            end
          DEFINE_METHODS
        end
        
        unless base_respond_to?("#{plural}=") || !attribute.allow_many?
          # logger.debug "Generating #{plural}= method"
          instance_eval <<-DEFINE_METHODS
            def #{plural}=(value)
              self['#{singular}'] = value
            end
          DEFINE_METHODS
        end
          
        unless base_respond_to? "#{singular}?"
          # logger.debug "Generating #{singular}? method"
          instance_eval <<-DEFINE_METHODS
            def #{singular}?
              self['#{singular}'].blank?
            end
          DEFINE_METHODS
        end

        unless base_respond_to?("#{plural}?") || !attribute.allow_many?
          # logger.debug "Generating #{plural}? method"
          instance_eval <<-DEFINE_METHODS
            def #{plural}?
              self['#{singular}'].blank?
            end
          DEFINE_METHODS
        end
        
      end
    end
  end
end

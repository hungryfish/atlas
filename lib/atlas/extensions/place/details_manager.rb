module Atlas
  module Extensions
    module Place
    
      # Similar to the photo manager, makes dealing with place_attributes and place_values a little easier,
      # more like the old PublicEarth::Db::Place::Details class (though not nearly as complicated).
      class DetailsManager
        include Enumerable 
        include XmlHelpers
        
        attr_reader :place, :attributes
        
        def initialize(place)
          @place = place
          @attributes = place.place_attributes.index_by(&:attribute_definition).symbolize_keys
          configure_attributes
        end

        def cache 
          PublicEarth::Db::Base.cache_manager
        end
        
        # Get the data set from the user or source contributing to the place.
        def source_data_set
          place.contributing && place.contributing.source_data_set || nil  
        end
        
        # Get the priorities associated with the category the place is in.
        def priorities(category_id = @place.category_id)
          return {} if category_id.nil?
          @priorities ||= cache.ns(:attribute_priorities).get_or_cache(category_id) do
            category = Atlas::Category.find(:first, :conditions => {:id => category_id}, :include => { :category_attributes => :definition })
            category && Hash[*(category.category_attributes.map {|ca| [ca.definition.name, ca.priority]}).flatten] || {}
          end
        end
        
        # Setup the ValuesManager for each place attribute.
        #
        # Set the priority values on all the place attributes, based on the category attributes.  Can't really
        # find a better way to do this, based on ActiveRecord vs. our data model.
        def configure_attributes
          @place.place_attributes.each do |pa|
            pa.details = self
            pa.priority = priorities[pa.attribute_definition] || 9999
          end
          
          # Add empty attributes, needed for place details edit
          priorities.keys.each do |attribute_name|
            add_attribute(attribute_name)
          end
        end
      
        # Used by both [] and define_attribute_methods, so we don't make double-queries creating
        # an attribute on the details object.
        def add_attribute(attribute_name)
          if !@attributes.has_key?(attribute_name.to_sym)
            # Create the PlaceAttribute record and a values manager for it; also hooks it into the Place model.
            pa = @place.place_attributes.build :attribute_definition => attribute_name
            pa.details = self
            pa.priority = priorities[attribute_name] || 9999
          
            # Record this thing in our local hash
            @attributes[attribute_name.to_sym] = pa
          end
          @attributes[attribute_name.to_sym]
        end
        
        # Get a place_attribute by name, e.g. :description or :state_province.  This method is pretty much the
        # core of the DetailsManager class.
        def [](attribute_name)
          name = attribute_name.to_s
          unless @attributes.has_key? name.to_sym 
            raise "Invalid attribute: #{name}!" unless cache.ns(:attributes_by_name).get(name)
            add_attribute(name)
          end
          apply_formatting(@attributes[name.to_sym])
        end

        # Shortcut to set an attribute value (or values; accepts an array too).  You can also use << on the 
        # attribute to add values to the list, e.g. more than one useful link.
        def []=(attribute_name, value)
          self[attribute_name].set(value)
        end
        
        # Return the number of attributes.
        def size
          place.place_attributes.inject(0) { |total, attribute| total + attribute.values.length }
        end
        alias :length :size
        
        def first
          @place.place_attributes.first
        end
        
        # Is this attribute defined for the place?  For example, place.details.include?(:description).
        def include?(attribute_name)
          @attributes.has_key?(attribute_name.to_sym) && self[attribute_name].present?
        end
        alias :has? :include?
        
        # Cycle over the PlaceAttribute objects.
        def each 
          @place.place_attributes.each { |attribute| yield attribute }
        end
        
        # Cycle over every PlaceAttribute with a value.
        def each_with_values
          @place.place_attributes.each { |attribute| yield attribute if attribute.values.present? }
        end
        
        # Interrupt the respond_to? call so we can trap for attributes.
        alias :base_respond_to? :respond_to?
        def respond_to?(method_name)
          method_name = method_name.to_s.underscore
          unless base_respond_to?(method_name)
            define_attribute_methods(method_name)
            base_respond_to?(method_name)
          end
        end

        # Take methods requested here and convert them to attribute values.  
        #
        # To set an attribute value:  attribute_name=(value)
        # To retrieve a value:  attribute_name
        #alias :default_method_missing :method_missing
        def method_missing(method_name, *args)
          attribute_name = method_name.to_s.underscore
          if respond_to?(attribute_name)
            send(attribute_name, *args)
          else
            super(method_name, *args)
          end
        end

        # Generates a method based on an attribute, if the attribute exists.
        def define_attribute_methods(method_name)
          attribute_name = method_name.to_s.gsub(/([=\?]?)$/, '').underscore
          modifier = $1
          
          Atlas::AttributeDefinition.named(attribute_name).present? || return 
          
          add_attribute(attribute_name)

          # Define Getter for attribute
          unless base_respond_to? attribute_name
            instance_eval <<-DEFINE_METHODS
              def #{attribute_name}
                self[:#{attribute_name}]
              end
            DEFINE_METHODS
          end

          # Define Setter for attribute
          unless base_respond_to? "#{attribute_name}="
            instance_eval <<-DEFINE_METHODS
              def #{attribute_name}=(value)
                self[:#{attribute_name}] = value
              end
            DEFINE_METHODS
          end
          
          # Define method to check for presence of attribute
          unless base_respond_to? "#{attribute_name}?"
            instance_eval <<-DEFINE_METHODS
              def #{attribute_name}?
                self[:#{attribute_name}].blank?
              end
            DEFINE_METHODS
          end

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
        def apply_formatting(value, format = place.content_format)
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
          place.place_attributes.each do |attribute|
            if(attribute.attribute_definition == "description" && !attribute.values.empty?)
              summary = RedCloth.new(attribute.first.to_s).to(RedCloth::Formatters::Summary)
              attributes_hash['summary'] = summary
            end
            attributes_hash[attribute.attribute_definition] = attribute.values.map { |a| apply_formatting(a.value) }
          end
          attributes_hash
        end

        def to_xml
          xml = XML::Node.new('details')
          xml.lang = 'en'

          to_hash.each do |attribute, values|
            array_node = XML::Node.new(attribute)
            array_node['name'] = attribute.titleize
            values.each do |value|
              array_node << xml_value('value', value)
            end
            xml << array_node
          end

          xml
        end
        
      end
    end
  end
end
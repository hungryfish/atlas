module Atlas
  class History
    
    module Convert

      module DataSet
        def self.to_xml(data_set)
          xml = XML::Node.new('data_set')
          xml['id'] = data_set.id
          xml << Convert::Source.to_xml(data_set.source)
        end
      end # module DataSet

      module Source
        def self.to_xml(source)
          xml = XML::Node.new('source')
          xml['id'] = source.id
          xml << XML::Node.new('name', source.name)
          xml << Convert::User.to_xml(source.user) if source.user?
          xml
        end
      end # module Source

      module User
        def self.to_xml(user)
          xml = XML::Node.new('user')
          xml['id'] = user.id
          xml << XML::Node.new('username', user.username)
          xml << XML::Node.new('email', user.email)
          xml
        end
      end # module User
      
      module Place
        def self.to_xml(place, options = {})
          xml = XML::Node.new('place')
          xml['id'] = place.id
          xml['name'] = place.name.to_s
          
          # If this place is newly created, let's show the intimate details...
          if options[:new_record]
            xml['created'] = (place.region.present? && 'region') || (place.route.present? && 'route') || 'point'
            xml << node('latitude', place.latitude)
            xml << node('longitude', place.longitude)
            xml << node('route', place.route.to_hash['route']) unless place.route.blank?
            xml << node('region', place.region.to_hash['region']) unless place.region.blank?
            xml << node('created_at', place.created_at.xmlschema)
          end
          
          xml << Convert::Category.to_xml(place.category) if [options[:include]].flatten.include? :category
          xml << Convert::Details.to_xml(place.place_attributes) if [options[:include]].flatten.include? :details
          xml
        end
        
        def self.node(name, contents)
          XML::Node.new(name, contents.to_s)
        end
        
      end # module Place

      module Details
        def self.to_xml(place_attributes)
          xml = XML::Node.new('details')
          place_attributes.each do |place_attribute|
            xml << Convert::Attribute.to_xml(attribute)
          end
          xml
        end
      end # module Details

      module Attribute
        def self.to_xml(attribute, options = {})
          xml = XML::Node.new('attribute')
          xml['name'] = attribute.attribute_definition
          xml['xml:lang'] = 'en' #attribute.language TODO: get language from values
          xml['type'] = attribute.definition.data_type
          xml['priority'] = attribute.priority.to_s
          
          #if attribute.values.length == 1
          #  Attribute.value(xml, attribute.values.first, options)
          #else
            Attribute.values(xml, attribute, options)
          #end
          
          xml
        end
        
        def self.values(xml, place_attribute, options={})
          
          # If it's deleted, these things make no sense!
          value = XML::Node.new('value') 
          value['id'] = place_attribute.id if place_attribute.id
          value << place_attribute.values.join(', ')
          xml << value
          
          
          # Has it been modified or deleted?  Include the original values?
          if [options[:include]].flatten.include?(:original) && place_attribute.values.any? {|v| v.value_changed?}
            original = XML::Node.new('original')
            value = XML::Node.new('value') 
            value << place_attribute.values.map(&:value_was).join(', ')
            original << value
            
            xml << original
          end
          xml
        end
        
      end # module Attribute

      module Category
        def self.to_xml(category)
          xml = XML::Node.new('category')
          xml['id'] = category.id
          xml['xml:lang'] = 'en'
          xml << category.name
          xml
        end
      end # module Category

    end # module Convert
    
  end
end
module PublicEarth
  module Db
    module CategoryExt
      module Formats
        
        # Used by the format generators...
        def to_hash
          category_hash = {
            :id => self.id,
            :name => self.name,
            :icons => {
              :icon => "http://www.publicearth.com/images/icons/places/icon/#{self.id}.png",
              :map_pin => "http://www.publicearth.com/images/icons/places/map_pin/#{self.id}.png",
              :small_pin => "http://www.publicearth.com/images/icons/places/small_pin/#{self.id}.png"
            }
          }

          if loaded? :attribute_definitions
            category_hash[:attributes] = @attributes[:attribute_definitions].values.map do |attribute|
              {
                :id => attribute.id,
                :name => attribute.name, 
                :label => attribute.name.to_s.titleize,
                :data_type => attribute.data_type,
                :allow_many => attribute.allow_many == 't',
                :readonly => attribute.readonly == 't'
              }
            end
          end
  
          category_hash[:parent] = self.parent.id if self.parent
  
          if loaded? :children
            category_hash[:children] = children.map { |c| c.to_hash }
          end

          category_hash[:places] = @attributes[:number_of_places].to_i if loaded? :number_of_places
          category_hash[:language] = @attributes[:language] || 'en'
  
          category_hash
        end

        # Return the category id, name, number of child categories, number of places in this 
        # category, and language (of the category name).
        def to_json(*a)
          to_hash.to_json
        end

        # Returns a Ruby LibXML Node.  If you want to return a single category to an application,
        # you should wrap this in a proper XML Document.
        #
        # === Sample XML Results
        # 
        #   <category id="Accommodations">
        #     <name xml:lang="en">Hotels &amp; Motels</name>
        #     <children>
        #       <!-- ...child categories XML... -->
        #     </children>
        #     <parent>parent_id</parent>
        #     <attributes>
        #       <!-- ...attribute definitions XML... -->
        #     </attributes>
        #   </category>
        #
        def to_xml
          xml = XML::Node.new('category')
          xml['id'] = self.id
          xml['slug'] = self.slug
  
          name = XML::Node.new('name') << as_cdata(self.name)
          name.lang = @attributes[:language] || 'en'
          xml << name
          xml << XML::Node.new('parent', self.parent.id) if loaded? :parent_id

          if loaded? :children
            children_node = XML::Node.new('children')
            children.each do |child_category|
              child_category.children
              children_node << child_category.to_xml
            end
            xml << children_node
          end
  
          if loaded? :attribute_definitions
            attrs_node = XML::Node.new('attributes')

            @attributes[:attribute_definitions].values.each do |ad|
              attrs_node << ad.to_xml
            end
    
            xml << attrs_node
          end

          xml << XML::Node.new('places', @attributes[:number_of_places].to_s) if loaded? :number_of_places
  
          xml
        end

        # Returns the Apple plist representation of this category.  Represents a single category
        # object; needs to be wrapped in an XML document and an array or dict.
        def to_plist
          to_hash.to_plist
        end
      end
    end
  end
end

module Atlas
  module Extensions
    module Category
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
            },
            :slug => self.slug
          }

          if self.attribute_definitions.loaded?
            category_hash[:attributes] = self.attribute_definitions.map do |attribute|
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

          if self.children.loaded?
            category_hash[:children] = self.children.map { |c| c.to_hash }
          end

          # category_hash[:places] = read_attribute(:total) || places.count
          category_hash[:updated_at] = read_attribute(:changed) || self.updated_at
          category_hash[:language] = self.language || 'en'

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
        def to_xml(options = {})
          xml = XML::Node.new('category')
          xml['id'] = self.id
          xml['slug'] = self.slug

          name = XML::Node.new('name') << as_cdata(self.name)
          name.lang = self.language || 'en'
          xml << name
          xml << XML::Node.new('parent', self.parent.id) if parent

          if children.loaded?
            children_node = XML::Node.new('children')
            children.each do |child_category|
              child_category.children
              children_node << child_category.to_xml
            end
            xml << children_node
          end

          if attribute_definitions.loaded?
            attrs_node = XML::Node.new('attributes')

            attribute_definitions.each do |ad|
              attrs_node << ad.to_xml
            end

            xml << attrs_node
          end

          if read_attribute :total
            xml << XML::Node.new('places', read_attribute(:total))
          elsif options[:include_place]
            xml << XML::Node.new('places', places.count.to_s)
          end

          changed = read_attribute(:changed)
          if changed.present?
            changed = Time.parse(changed) if changed.kind_of? String
            xml << XML::Node.new('updated_at', changed.xmlschema) 
          end

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

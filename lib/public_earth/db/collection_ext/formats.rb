module PublicEarth
  module Db
    module CollectionExt
      
      # Output formats for the Collection models:  JSON, KML, RSS, XML, etc.  
      #
      # TODO:  Not all formats are implemented yet!
      module Formats

        # Generate the GeoRSS XML for a collection.  Pass in a reference to a builder for this XML to
        # attach itself to.  If none is supplied, a full GeoRSS XML document will be returned.
        def to_georss(builder = nil)
          # TODO!
        end

        def to_hash
          hash = {
            'id' => self.id,
            'name' => self.name.to_s,
            'description' => @attributes[:description],
            'created_at' => @attributes[:created_at],
            'updated_at' => @attributes[:updated_at],
            'slug' => self.slug,
            'icon' => @attributes[:icon],
            'rating' => self.rating,
          }
          hash['created_by'] = self.created_by.to_hash if self.created_by
          hash
        end
        
        # Render JSON from collection.
        def to_json(*a)
          # options = a.last.kind_of?(Hash) && a.last || {}
          # 
          # hash = to_hash
          
          # unless options[:exclude] == :places || (options[:exclude].kind_of?(Array) && options[:exclude].include?(:places))
          #   hash[:places] = self.places(options)
          # end
          # 
          # # TODO:  This doesn't have the best performance...
          # unless options[:exclude] == :categories || (options[:exclude].kind_of?(Array) && options[:exclude].include?(:categories))
          #   hash[:categories] = self.what.categories
          # end
          # 
          # # TODO:  This doesn't have the best performance...
          # unless options[:exclude] == :sources || (options[:exclude].kind_of?(Array) && options[:exclude].include?(:sources))
          #   hash[:sources] = self.what.sources
          # end
          
          to_hash.to_json
        end

        # Returns a Ruby LibXML Node.  If you want to return a single collection to an application,
        # you should wrap this in a proper XML Document.
        #
        # === Sample XML Results
        # 
        #   <collection id="23423-2iooijsadf-243iorwekla-adsfj4">
        #     <name xml:lang="en">Favorite Restaurants</name>
        #     <description>...</description>
        #     <slug>favorite-restaurants</slug>
        #     <created_by>...</created_by>
        #   </collection>
        #
        def to_xml
          xml = XML::Node.new('collection')
          xml['id'] = self.id
  
          name = XML::Node.new('name') << XML::Node.new_cdata(self.name.to_s)
          name.lang = @attributes[:language] || 'en'
          xml << name

          xml << xml_value(:slug, self.slug)

          unless @attributes[:description].blank?
            desc = XML::Node.new('description') << XML::Node.new_cdata(self.description.to_s)
            desc.lang = @attributes[:language] || 'en'
            xml << desc
          end
          
          xml << XML::Node.new('created_at', Time.parse(self.created_at).xmlschema) if @attributes[:created_at]
          xml << XML::Node.new('updated_at', Time.parse(self.updated_at).xmlschema) if @attributes[:updated_at]

          xml << self.created_by.to_xml
          
          xml
        end

        # Returns the Apple plist representation of this collection.  Represents a single collection
        # object; needs to be wrapped in an XML document and an array or dict.
        def to_plist
          (to_hash - 'place_id').to_plist
        end
      end
    end
  end
end

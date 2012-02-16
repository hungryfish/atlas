module Atlas
  module Extensions
    module Geography
      module Formats
        
        def to_hash
          hash = {
            :id => self.id,
            :name => self.label,              # deprecated, but for backwards compat.
            :label => self.label,
            :score => self.score.to_i,
            :type => 'geography',             # deprecated, but for backwards compat.
            :what => self.what
          }
          hash.merge bounds
        end
        
        def to_json
          to_hash.to_json
        end

        def to_plist
          to_hash.to_plist
        end

        def to_xml
          xml = XML::Node.new('where')

          xml << xml_value(:name, self[:label])     # name is deprecated for label
          xml << xml_value(:label, self[:label])
          xml << xml_value(:score, self[:score])
          xml << xml_value(:type, 'geography')      # deprecated
          xml << xml_value(:what, self[:what])

          xml << xml_value(:latitude, self[:latitude])
          xml << xml_value(:longitude, self[:longitude])
          
          if (self[:sw])
            sw = XML::Node.new('sw')
            sw << xml_value(:latitude, self[:sw][:latitude]) 
            sw << xml_value(:longitude, self[:sw][:longitude]) 
            xml << sw
          end

          if (self[:ne])
            ne = XML::Node.new('sw')
            ne << xml_value(:latitude, self[:ne][:latitude]) 
            ne << xml_value(:longitude, self[:ne][:longitude]) 
            xml << ne
          end

          xml
        end

      end
    end
  end
end



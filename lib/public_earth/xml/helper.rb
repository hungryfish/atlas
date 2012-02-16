# XML helper methods
module PublicEarth
  module Xml
    module Helper
  
      # Return either a plain string if no special characters are there, or a CDATA-wrapped string if there
      # are escapable characters.
      def as_cdata(value)
        value && value =~ /[\&\<\>]/ && XML::Node.new_cdata(value.to_s) || value.to_s
      end
      
      # Add an XML tag of the given name with the given value.  If the value has escapable characters,
      # wraps the value in a CDATA tag.
      def xml_value(tag_name, value, properties = {})
        tag = XML::Node.new(tag_name.to_s) 
        properties.each do |k, v|
          tag[k.to_s] = v.to_s
        end
        tag << as_cdata(value)
        tag
      end
      
    end
  end
end

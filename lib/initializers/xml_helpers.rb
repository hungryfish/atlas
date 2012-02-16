# XML helper methods
module XmlHelpers  
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
  
  # Expects the extending class to have a to_xml method that returns a Ruby LibXML XML::Node
  # object, which will then be wrapped in a generic XML::Document and returned.  Useful if
  # you care enough to send only one of an object!
  def xml_document
    xml = XML::Document.new
    xml.root = self.to_xml
    xml
  end
  
  # Convert the object to an Apple PropertyList.  Does not have the XML document wrapper, in
  # case you want to include it as part of an array or other objects.
  def to_plist
    attributes.to_plist
  end
  
end

ActiveRecord::Base.send(:include, XmlHelpers)

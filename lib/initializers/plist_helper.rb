require 'xml'
require 'action_controller'
require 'public_earth/xml/helper'

# Upgrade these data types to be able to render themselves as Apple PropertyList XML documents.

Mime::Type.register "text/xml", :plist

class Object
  # Expects the extending class to have a to_plist method, and returns the single object 
  # representation as an Apple PropertyList XML document.
  def plist_document
    xml = XML::Document.new
    XML::Dtd.new('-//Apple Computer//DTD PLIST 1.0//EN',
        'http://www.apple.com/DTDs/PropertyList-1.0.dtd', 'plist', xml, true)
    xml.root = plist = XML::Node.new('plist')
    plist['version'] = '1.0'
    
    if self.respond_to? :to_plist
      plist << self.to_plist
    end
    
    xml
  end
end

class NilClass
  include PublicEarth::Xml::Helper

  def to_plist
    xml_value('string', self)
  end
end
  
class String
  include PublicEarth::Xml::Helper
  
  def to_plist
    xml_value('string', self)
  end
end

class Fixnum
  def to_plist
    XML::Node.new('integer', self.to_s)
  end
end

class Float
  def to_plist
    XML::Node.new('real', self.to_s)
  end
end

class Date
  def to_plist
    XML::Node.new('date', to_local_time.to_plist)
  end
  
  def to_gm_time
    to_time(new_offset, :gm)
  end

  def to_local_time
    to_time(new_offset(DateTime.now.offset-offset), :local)
  end

  private

    def to_time(dest, method)
      usec = (dest.sec_fraction * 60 * 60 * 24 * (10**6)).to_i
      Time.send(method, dest.year, dest.month, dest.day, dest.hour, dest.min, dest.sec, usec)
    end
end

class Time
  def to_plist
    XML::Node.new('date', xmlschema)
  end
end

class TrueClass
  def to_plist
    XML::Node.new('true')
  end
end

class FalseClass
  def to_plist
    XML::Node.new('false')
  end
end

class Array
  def to_plist
    array_node = XML::Node.new('array')
    self.each do |entry|
      array_node << entry.to_plist if entry.respond_to? :to_plist
    end
    array_node
  end
end

class Hash
  include PublicEarth::Xml::Helper
  
  def to_plist
    dict_node = XML::Node.new('dict')
    self.each do |key, value|
      if value.respond_to? :to_plist
        dict_node << xml_value(:key, key)
        dict_node << value.to_plist
      end
    end
    dict_node
  end
end


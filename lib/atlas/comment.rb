module Atlas
  class Comment < ActiveRecord::Base
    belongs_to :user, :class_name => 'Atlas::User'
    belongs_to :place, :class_name => 'Atlas::Place'
    
    validates_presence_of :place
    validates_presence_of :user
    validates_presence_of :content

    def to_hash
      {
        :id => self.id,
        :content => self.content,
        :user => self.user,
        :created_at => self[:created_at].xmlschema,
      }
    end
  
    def to_json
      to_hash.to_json
    end
  
    def to_plist
      to_hash.to_plist
    end
  
    def to_xml
      xml = XML::Node.new('comment')
      xml['id'] = self.id
      
      xml << self.user.to_xml
      xml << xml_value(:content, self.content)
      xml << xml_value(:created_at, self[:created_at].xmlschema)
    
      xml
    end
  end
end
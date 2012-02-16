module PublicEarth
  module Db

    # Discussions have many comments.
    class Comment < PublicEarth::Db::Base
      def user
        query_for :user do
          PublicEarth::Db::User.find_by_id!(self.user_id)
        end
      end
  
      def to_hash
        {
          :id => self.id,
          :content => self.content,
          :user => self.user,
          :created_at => self[:created_at] && Time.parse(self[:created_at]).xmlschema,
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
        xml << xml_value(:created_at, Time.parse(self[:created_at]).xmlschema) if self[:created_at]
      
        xml
      end
      
    end
  end
end
module Atlas
  module ReadOnly
    class Place < Atlas::Place
      attr_accessor :place_attributes, :contributors, :tags, :features, :moods, :creator
    
      def initialize(attributes = nil)
        super
        @place_attributes = Atlas::Util::ArrayAssociation.new self, Atlas::ReadOnly::PlaceAttribute
        @contributors = Atlas::Util::ArrayAssociation.new self, Atlas::Source
        @tags = Atlas::Util::ArrayAssociation.new self, Atlas::Tag
        @features = Atlas::Util::ArrayAssociation.new self, Atlas::Feature
        @moods = Atlas::Util::ArrayAssociation.new self, Atlas::Mood
      end
    
      def creator
        @creator ||= Atlas::Source.find :first,
            :joins => "left join contributors on contributors.source_id = sources.id",
            :conditions => ["place_id = ? and creator is true", self.id]
      end
      
    end
  end
end
    
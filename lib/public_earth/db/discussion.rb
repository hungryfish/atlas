module PublicEarth
  module Db

    # Manage discussions, aka forum topics.
    class Discussion < PublicEarth::Db::Base
    
      attr_accessor :comment
      
      class << self
      
        # Return the discussions for the given place.  Does not return the comments associated with the discussion.
        def for_place(place_id)
          PublicEarth::Db::Place.many.discussions(place_id).map { |result| new(result) }
        end
        
        # Look up a discussion by its ID.  Raises an exception if the discussion does not exist.
        #
        # If you'd like to load the comments for the discussion, set include_comments to true.  Typically
        # you don't have to, as the place.discussions() method will get discussions and comments together
        # in a single database call and sort everything out for you.
        def find_by_id!(id)
          discussion = new(one.find_by_id(id) || raise(RecordNotFound, "Unable to find a discussion for #{id}."))
          discussion.load_comments
          discussion
        end
        alias_no_exception :find_by_id!
        
        # Create a discussion.  Place and comment are optional.
        def create(subject, user, comment = nil, place = nil)
          discussion = new
          if subject.blank?
            discussion.errors.add(:subject, 'Subject cannot be blank')
            discussion.subject = ""
          end
          
          if user.blank?
            discussion.errors.add(:user, 'Invalid user')
          end
          
          if discussion.errors.empty?
            discussion.attributes = one.create(subject, comment, user.id, place && place.id) || raise(CreateFailed, "Unable to create a discussion about \"#{subject}\".")
            discussion.load_comments
          end
          
          discussion # always return discussion even if validations fail
        end
      
      end # class << self
    
      def initialize(attributes = {})
        super(attributes)
        @comments = []
      end

      def load_comments
        @comments = PublicEarth::Db::Discussion.many.comments(self.id).map { |attributes| PublicEarth::Db::Comment.new(attributes) } 
      end
    
      # Return the list of comments for the discussion.
      def comments
        @comments
      end

      def comments=(value)
        @comments = value
      end
    
      # Add an existing comment to the discussion.  This is used by place.discussions().  It doesn't change 
      # the comment at all, just adds it to the cached array.
      def <<(comment)
        @comments << comment
      end
    
      # Add a new comment to this discussion
      def make_comment(content, user)
        return if content.blank?
        comment = PublicEarth::Db::Comment.new(PublicEarth::Db::Discussion.one.comment(self.id, user.id, content))
        @comments << comment
        comment
      end
      
      def to_hash
        discussion_hash = {
          :id => self.id,
          :subject => self[:subject],
          :created_at => self[:created_at] && Time.parse(self[:created_at]).xmlschema,
          :updated_at => self[:updated_at] && Time.parse(self[:updated_at]).xmlschema
        }
        
        discussion_hash[:comments] = comments.map { |c| c.to_hash } if @comments

        discussion_hash
      end
      
      def to_json
        to_hash.to_json
      end
      
      def to_plist
        to_hash.to_plist
      end
      
      def to_xml
        xml = XML::Node.new('discussion')
        xml['id'] = self.id
        
        xml << xml_value(:subject, self[:subject]) if self[:subject]
        xml << xml_value(:created_at, Time.parse(self[:created_at]).xmlschema) if self[:created_at]
        xml << xml_value(:updated_at, Time.parse(self[:updated_at]).xmlschema) if self[:updated_at]
        
        if @comments
          comments_xml = XML::Node.new('comments')
          comments_xml['count'] = number_of_comments.to_i.to_s
          comments.each do |comment|
            comments_xml << comment.to_xml
          end
          xml << comments_xml
        end
        
        xml
      end
    end
  end
end
module Atlas
  module ReadOnly
    class Category < Atlas::Category
      attr_accessor :parent, :children
    
      def initialize(attributes = nil)
        super
        @parent = nil
        @children = Atlas::Util::ArrayAssociation.new self, Atlas::ReadOnly::Category
      end

      def children 
        @children ||= Atlas::Util::ArrayAssociation.new self, Atlas::ReadOnly::Category
      end
    end
  end
end

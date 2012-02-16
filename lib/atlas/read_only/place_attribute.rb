module Atlas
  module ReadOnly
    class PlaceAttribute < Atlas::PlaceAttribute
      attr_accessor :values
    
      def initialize(attributes = nil)
        super
        @values = Atlas::Util::ArrayAssociation.new self, Atlas::PlaceValue, :place_attribute_id
      end
      
    end
  end
end
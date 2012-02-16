module PublicEarth
  module Db
    class Many

      attr_accessor :schema_name
    
      def initialize(schema_name)
        self.schema_name = schema_name
      end
    
      # Convert a request for many records to a database proxy request.
      def method_missing(method_name, *parameters)
        PublicEarth::Db::Base.call("#{schema_name}.#{method_name}", *parameters)
      end
    
    end
  end
end
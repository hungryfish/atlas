module PublicEarth
  module Db
    class One
    
      attr_accessor :schema_name
    
      def initialize(schema_name)
        self.schema_name = schema_name
      end
    
      # Convert a request for a single record to a database proxy request.
      def method_missing(method_name, *parameters)
        PublicEarth::Db::Base.call_for_one("#{schema_name}.#{method_name}", *parameters)
      end

    end
  end
end
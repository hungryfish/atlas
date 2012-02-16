module PublicEarth
  module Db
    module Helper
      module PredefineAttributes

        def inherited(subclass)
          subclass.class_eval do
            @@predefined_attributes = []
          end
        end
        
        # Return the array of predefined attributes.
        def predefined_attributes
          @@predefined_attributes ||= []
        end
        
        # By default, attributes on a model are only instantiated when they have been loaded from the
        # database or some other source, or when they have been specifically set.  This can cause 
        # problems for forms that expect methods to exist on those attributes before they have been
        # requested from the database, such as in HTML forms.
        #
        # The predefine method may be called to configure those required attributes ahead of time with
        # a nil value.  They will then properly respond to accessor requests.
        def predefine(*attributes)
          attributes.each do |attribute|
            @@predefined_attributes << attribute.to_sym
          end
        end
        
      end
    end
  end
end
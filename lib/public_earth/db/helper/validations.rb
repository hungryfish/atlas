module PublicEarth
  module Db
    module Helper
      class Errors
        include Enumerable
      
        def initialize(base) # :nodoc:
          @base, @errors = base, {}
        end

        # Adds an error to the base object instead of any particular attribute. This is used
        # to report errors that don't tie to any specific attribute, but rather to the object
        # as a whole. These error messages don't get prepended with any field name when iterating
        # with each_full, so they should be complete sentences.
        def add_to_base(msg)
          add(:base, msg)
        end
      
        def on(attribute)
          errors = @errors[attribute.to_s]
          return nil if errors.nil?
          errors.size == 1 ? errors.first : errors
        end

        alias :[] :on
            
        def on_base
          on(:base)
        end

        # Adds an error message (+msg+) to the +attribute+, which will be returned on a call to <tt>on(attribute)</tt>
        # for the same attribute and ensure that this error object returns false when asked if <tt>empty?</tt>. More than one
        # error can be added to the same +attribute+ in which case an array will be returned on a call to <tt>on(attribute)</tt>.
        # If no +msg+ is supplied, "invalid" is assumed.
        def add(attribute, msg = @@default_error_messages[:invalid])
          @errors[attribute.to_s] = [] if @errors[attribute.to_s].nil?
          @errors[attribute.to_s] << msg
        end

        def each
          @errors.each_key { |attr| @errors[attr].each { |msg| yield attr, msg } }
        end
      
        def each_full
          full_messages.each { |msg| yield msg }
        end
      
        def full_messages
          full_messages = []

          @errors.each_key do |attr|
            @errors[attr].each do |msg|
              next if msg.nil?

              if attr == "base"
                full_messages << msg
              else
                full_messages << msg
              end
            end
          end
          full_messages
        end
      
        # Returns true if no errors have been added.
        def empty?
          @errors.empty?
        end
      
        # Removes all errors that have been added.
        def clear
          @errors = {}
        end
      
        # Returns the total number of errors added. Two errors added to the same attribute will be counted as such.
        def size
          @errors.values.inject(0) { |error_count, attribute| error_count + attribute.size }
        end
      
        alias_method :count, :size
        alias_method :length, :size
      
      end
    
      module Validations
        def self.included(receiver)
          receiver.send :include, InstanceMethods
        end
      
        # Returns the Errors object that holds all information about attribute error messages.
        module InstanceMethods
          def errors
            @errors ||= Errors.new(self)
          end    
        end
      end    
    end
  end
end

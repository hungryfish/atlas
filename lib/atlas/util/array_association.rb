module Atlas
  module Util
    
    # Make an array of objects appear like an ActiveRecord association, adding build, create, exists?, etc.
    # methods to the Array class.
    #
    # TODO:  This implementation does not handle :through relationships properly!
    #
    # Note that this should only be used in a read-only situation.  You cannot save 
    class ArrayAssociation < Array
     
      attr_reader :owner, :for_class, :foreign_key
      
      # Indicate the class this array association will hold, e.g. Atlas::Source.
      def initialize(owner, for_class, foreign_key = nil)
        @owner = owner
        @for_class = for_class
        @foreign_key = foreign_key && foreign_key.to_sym
      end
      
      alias :add_one :<<
      def <<(*objects)
        objects.flatten.each { |o| add_one o if o.kind_of? for_class }
      end
      
      alias :delete_without_many :delete
      def delete(*objects)
        objects.each { |o| delete_without_many o }
      end
      
      def find(*args)
        if @foreign_key
          for_class.with_scope(:find => { :conditions => { @foreign_key => owner } }) do
            for_class.find(*args)
          end
        else
          for_class.find(*args)
        end
      end
      
      def exists?(*args)
        @exists ||= (!empty? || find(:first, :limit => 1).present?)
      end
      
      def loaded?
        true
      end
      
      def build(*attribute_arrays)
        built = attribute_arrays.map do |attributes|
          if @foreign_key 
            o = for_class.new(attributes.merge(@foreign_key => owner))
          else
            o = for_class.new(attributes)
          end
          add_one o
          o
        end
        built.length == 1 && built.first || built
      end
      alias :create :build

    end
  end
end

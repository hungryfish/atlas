module Atlas
  module Extensions
    module Identifiable
      module ClassMethods
        def identified(id_or_slug, *args)
          options = args.extract_options!
          field = options.delete(:field) || 'slug'
          self.find(:first, options.reverse_merge(:conditions => ["#{table_name}.id = ? OR #{table_name}.#{field} = ?", id_or_slug, id_or_slug]))
        end        

        def identified!(id_or_slug, *args)
          identified(id_or_slug, *args) || raise(ActiveRecord::RecordNotFound, "No #{class_name} found for #{id_or_slug}")
        end        
      end
      
      def self.included(receiver)
        receiver.extend ClassMethods
      end      
    end
  end
end


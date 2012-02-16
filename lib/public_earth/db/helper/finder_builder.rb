module PublicEarth
  module Db
    module Helper
      module FinderBuilder
   
        # Generate finder methods based on the given attributes.  For example, 
        #
        #   finder :name, :email, :username_and_password
        #
        # will create six methods on the class:
        #
        # * find_by_name(name) -- returns nil if the record does not exist
        # * find_by_name!(name) -- raises an exception if the record does not exist
        # * find_by_email(email) -- returns nil if the record does not exist
        # * find_by_email!(email) -- raises an exception if the record does not exist
        # * find_by_username_and_password(username, password) -- returns nil if the record does not exist
        # * find_by_username_and_password!(username, password) -- raises an exception if the record does not exist
        #
        # Notice the last methods see the "and" between the attributes and attempts to create methods
        # that match for that scenario, similar to ActiveRecord.  
        #
        # Behind the scenes, the method will expect two stored procedures for each attribute:  find_by_name,
        # and find_by_name_ne.  The first should raise an exception if the record cannot be found.  The other
        # should just return null (_ne = "no exception").
        #
        # Finder expects to return a single record.  If you need a finder to return a number of records, try
        # find_many.  It operates the same as finder, but returns an array of results.
        #
        # You may pass in a :cache option to indicate that you would like to cache the results of this finder
        # in Memcache or another caching engine, as defined by the cache_manager method in PublicEarth::Db::Base
        # (declared in the environment configuration files).  
        #
        #   class PublicEarth::Db::Category < PublicEarth::Db::Base
        #     finder :name, :cache => true
        #     finder :name, :cache => :my_sample_cache
        #   end
        #
        # The first example above will create a cache namespace (using the cache_manager) based on the name of 
        # the class and the name of the finder attribute.  In this case, it will be "categories_by_name".
        #
        # In the second example, the cache name will simply be what was submitted in the :cache option, 
        # "my_sample_cache".
        #
        # TODO:  Create a separate "cache" method that will generate a cached result based on the arguments
        # passed into the function to be cached
        def finder(*attributes)
          options = attributes.last.kind_of?(Hash) && attributes.pop || {}
          
          # Cache results in MemCache or some other caching engine?
          if options[:cache]
            attributes.each do |attribute|

              if options[:cache].kind_of?(String) || options[:cache].kind_of?(Symbol)
                cache = options[:cache]
              else
                cache = "#{name.sub(/\APublicEarth\:\:Db\:\:/, '').underscore.pluralize}_by_#{attribute}"
              end

              self.class_eval %{
                def self.find_by_#{attribute}!(*args)
                  raise RecordNotFound, "Invalid request:  a single argument is required for find_by_#{attribute}!" unless args.length == 1
                  cache_manager.ns(:#{cache}).get_or_cache(args.first) do
                    new(one.find_by_#{attribute}(*args))
                  end
                rescue
                  raise(RecordNotFound, "Unable to locate #{name} for \#{args.inspect}")
                end

                def self.find_by_#{attribute}(*args)
                  raise RecordNotFound, "Invalid request:  a single argument is required for find_by_#{attribute}!" unless args.length == 1
                  cache_manager.ns(:#{cache}).get_or_cache(args.first) do
                    construct_if_found one.find_by_#{attribute}(*args)
                  end
                end
              }, __FILE__, __LINE__
            end
          else
            attributes.each do |attribute|
              self.class_eval %{
                def self.find_by_#{attribute}!(*args)
                  begin
                    new(one.find_by_#{attribute}(*args))
                  rescue
                    raise RecordNotFound, "Unable to locate #{name} for \#{args}."
                  end
                end

                def self.find_by_#{attribute}(*args)
                  construct_if_found one.find_by_#{attribute}_ne(*args)
                end
              }, __FILE__, __LINE__
            end
          end
        end

        # Same as finder, but returns many records instead of a single result.  Note that find_many and
        # finder will overwrite each other if you use the same attribute for both!  You only need the
        # find_by_... method, not the find_by_..._ne.  If no results are found from this method, it will
        # return an empty set.
        def find_many(*attributes)
          attributes.each do |attribute|
            self.class_eval %{
              def self.find_by_#{attribute}(*args)
                many.find_by_#{attribute}(*args).map {|result| new(result)}
              end
            }, __FILE__, __LINE__
          end
        end

      end
    end
  end
end
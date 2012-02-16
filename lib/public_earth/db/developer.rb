module PublicEarth
  module Db

    class Developer < PublicEarth::Db::Base
  
      finder :key, :user

      class << self
        
        # Look up a developer by his or her key or internal ID.  Looks in the cache for the developer first.
        def find_by_id(id)
          cache = PublicEarth::Db::Base.cache_manager.ns(:developers_by_key)
          developer = cache.get(id)
          unless developer
            developer = new PublicEarth::Db::Developer.one.find_by_id(id)
            if developer
              cache.put(developer.id, developer, 14400)         # 4 hours
              cache.put(developer.key, developer, 14400)
            end
          else
            logger.debug("Retrieved developer #{id} from cache.")
          end
          developer
        end
        
        # TODO:  find_by_id! does not cache its result!
        
        # Create a new developer account.
        def create(user_id, url, key = nil)
          developer = new PublicEarth::Db::Developer.one.create(user_id, key, url)
          cache_manager.ns(:developers_by_key).put(developer.id, developer, 14400)
          cache_manager.ns(:developers_by_key).put(developer.key, developer, 14400)
        end
        
        # Get an array of valid URLs for the given developer key.  
        def valid_urls(key)
          cache_manager.ns(:developer_urls_by_key).get_or_cache(key, 14400) do |k|
            PublicEarth::Db::Developer.many.valid_urls(k).map { |result| result['url'] }
          end
        end
        
        # Get the roles available to the developer.
        #
        # TODO:  This is not functional yet!!!  Needs database tables for roles and tests around procedures.
        def valid_roles(key)
          cache_manager.ns(:developer_roles_by_key).get_or_cache(key, 14400) do |k|
            PublicEarth::Db::Developer.many.valid_roles(k).map { |result| result['role'] }
          end
        end
        
        # Increments the limit counter, if the user is limited by requests, and returns true
        # if the developer has hit that limit.  If under the limit or no limits exist, returns
        # false.
        #
        # TODO:  This is not functional yet!!!
        def limit?(key)
          return false
          
          
          # TODO :: RECORD REQUESTS EFFICIENTLY!!!
          
          developer = PublicEarth::Db::Developer.find_by_id(key)
          counter = cache_manager.ns(:developer_requests_by_key).get(key, 0) + 1
          if developer.resource_limits && counter > developer.resource_limits
            true
          else
            # cache_manager.ns(:developer_requests_by_key).put(key, counter)
            # TODO!!!
          end
        end
      end
      
      # Return an array of URLs associated with this account.
      def valid_urls
        @valid_urls ||= PublicEarth::Db::Developer.valid_urls(self.key)
      end

      # Return an array of roles associated with this account.
      def valid_roles
        @valid_roles ||= PublicEarth::Db::Developer.valid_roles(self.key)
      end
      
      def resource_limit
        @attributes[:resource_limit] && @attributes[:resource_limit].to_i || nil
      end
    end
  end
end
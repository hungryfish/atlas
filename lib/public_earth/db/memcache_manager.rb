require 'memcache'

module PublicEarth
  module Db

    # Another layer on top of memcache-client.
    class MemcacheManager
      attr_reader :memcache
  
      # Calls to the cache server are typically made through a Namespace, which prepends the
      # namespace name on the front of the key before reading or writing to the cache.
      class Namespace
        def initialize(name, cache)
          @name = name.to_s
          @cache = cache
        end
  
        def key_in_ns(key)
          "#{@name}/#{clean(key)}"
        end
        
        def clean(key)
          key.to_s.gsub(/[^\w\:\-]/, '_')
        end
       
        # Call to see if the memcache client is attached to memcached servers.  If not, none of
        # these commands will cache anything (but they will still appear to work...). 
        def servers?
          !@cache.servers.blank?
        #   
        #   return false if @cache.servers.blank?
        #   @cache.stats
        #   true
        # rescue
        #   false
        end
        
        # Get the value from the cache.  If it doesn't exist, return the default.  The key
        # attribute may be either a single key or an array of keys.  If you request an array
        # of keys, default will be ignored; if no results are found, an empty hash is returned.
        def get(key, default = nil)
          return default unless servers?
          if key.kind_of? Array
            @cache.get_multi(key_in_ns(key))
          else
            @cache.get(key_in_ns(key)) || default  
          end
        end
  
        # Similar to get, but if the key is not in the cache, the block is run and its result is 
        # placed in the cache under the key.  The reason we use a block is so the default value isn't
        # queried every time the method is called, only when the key isn't there.
        #
        # The key is passed into the block.
        #
        # Expiry is in seconds.
        def get_or_cache(key, expiry = 0, &block)
          return block.call(key) unless servers?
          get(key) || put(key, block.call(key))
        end
        
        # Put the value in the cache.  You may also set an optional expiration time; defaults
        # to never expires.  If you set the value to nil or an empty string or array, removes
        # the key from the cache.
        #
        # Expiry is in seconds.
        def put(key, value, expiry = 0)
          if servers?
            unless value.blank?
              if @cache.get(key_in_ns(key), true)
                @cache.set(key_in_ns(key), value, expiry, false)
              else
                @cache.add(key_in_ns(key), value, expiry, false)
              end
            else
              @cache.delete(key_in_ns(key)) if @cache.get(key_in_ns(key), true)
            end
          end
          value
        end
        
        # Delete the given key.
        def delete(key)
          put(key, nil) if servers?
        end
        alias :remove :delete
      end

      def initialize(servers = nil, logger = nil)
        @memcache = MemCache.new(servers, :multithread => true, :logger => logger)
      end

      # Return a reference to the given namespace.  Just prepends the prefix onto the name of
      # each key requested through get.
      # 
      # Leave prefix out of the request add keys directly, with no prefix.
      def namespace(prefix = nil)
        Namespace.new(prefix, @memcache)
      end
      alias :root :namespace
      alias :ns :namespace
      
      def flush
        @memcache.flush_all
      end

      def stats
        @memcache.stats
      end
    end
    
  end
end
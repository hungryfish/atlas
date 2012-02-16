# Provide the PublicEarth cache manager to ActiveRecord:Base models.
module CacheManager 
  
  def cache_manager
    PublicEarth::Db::Base.cache_manager
  end
  
end

ActiveRecord::Base.extend(CacheManager)


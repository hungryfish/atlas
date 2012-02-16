module PublicEarth
  module Db
    # Find featured links for the home page
    # Links are managed with the admin tool
    class FeaturedLink < PublicEarth::Db::Base
      class << self
        def all
          PublicEarth::Db::FeaturedLink.many.all
        end
        
        def all_active
          PublicEarth::Db::FeaturedLink.many.all_active
        end
      end
    end
  end
end

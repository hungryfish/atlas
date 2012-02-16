require 'active_record'
require 'public_earth/postgresql_bug'

module Atlas
  
  autoload :Place, 'atlas/place'
  autoload :PlaceAttribute, 'atlas/place_attribute'
  autoload :PlaceValue, 'atlas/place_value'
  autoload :Category, 'atlas/category'
  autoload :RelatedCategory, 'atlas/related_category'
  
  module ReadOnly
    autoload :Place, 'atlas/read_only/place'
    autoload :PlaceAttribute, 'atlas/read_only/place_attribute'
    autoload :Category, 'atlas/read_only/category'
  end

  module Util
    autoload :ArrayAssociation, 'atlas/util/array_association'
    autoload :PolylineEncoder, 'atlas/util/polyline_encoder'
  end
end
  
module PublicEarth
  
  module Xml
    autoload :Helper, 'public_earth/xml/helper'
  end
  
  module Db
    
    autoload :AnonymousUser, 'public_earth/db/anonymous_user'
    autoload :Attribute, 'public_earth/db/attribute'
    autoload :Base, 'public_earth/db/base'
    autoload :Category, 'public_earth/db/category'
    autoload :Collection, 'public_earth/db/collection'
    autoload :Comment, 'public_earth/db/comment'
    autoload :Contributor, 'public_earth/db/contributor'
    autoload :DataSet, 'public_earth/db/data_set'
    autoload :Details, 'public_earth/db/details'
    autoload :Developer, 'public_earth/db/developer'
    autoload :DeviceQueue, 'public_earth/db/device_queue'
    autoload :Discussion, 'public_earth/db/discussion'
    autoload :Featured, 'public_earth/db/featured'
    autoload :FeaturedLink, 'public_earth/db/featured_link'
    autoload :History, 'public_earth/db/history'
    autoload :Many, 'public_earth/db/many'
    autoload :MemcacheManager, 'public_earth/db/memcache_manager'
    autoload :One, 'public_earth/db/one'
    autoload :Place, 'public_earth/db/place'
    autoload :PlacePhoto, 'public_earth/db/place_photo'
    autoload :Source, 'public_earth/db/source'
    autoload :Tag, 'public_earth/db/tag'
    autoload :User, 'public_earth/db/user'

    module GeoIp
      autoload :Location, 'public_earth/db/geo_ip/location'
    end

    module Helper
      autoload :BoundingBox, 'public_earth/db/helper/bounding_box'
      autoload :CreateTableGuids, 'public_earth/db/helper/create_table_guids'
      autoload :FinderBuilder, 'public_earth/db/helper/finder_builder'
      autoload :GeneralFind, 'public_earth/db/helper/general_find'
      autoload :PredefineAttributes, 'public_earth/db/helper/predefine_attributes'
      autoload :Relations, 'public_earth/db/helper/relations'
      autoload :StateMonitor, 'public_earth/db/helper/state_monitor'
      autoload :Validations, 'public_earth/db/helper/validations'
    end
  
  end # module Db

  # Solr search integration
  autoload :Search, 'public_earth/search'
  module Search
    autoload :CollectionResults, 'public_earth/search/collection_results'
    autoload :PlaceResults, 'public_earth/search/place_results'
    autoload :Solr, 'public_earth/search/solr'
  end
end    

# Configure logging for the search services
PublicEarth::Search::Solr.logger = ActiveRecord::Base.logger

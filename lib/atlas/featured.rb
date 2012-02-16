module Atlas
  class Featured < ActiveRecord::Base
    belongs_to :featureable, :polymorphic => true
    
    # TODO: make this only return sources "WHERE icon_path IS NOT NULL"
    named_scope :partners, :conditions => "featureable_type='Atlas::Source'", :include => :featureable
  end
end

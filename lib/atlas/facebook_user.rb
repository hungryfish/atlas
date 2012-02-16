module Atlas
  class FacebookUser < ActiveRecord::Base
    belongs_to :user, :class_name => 'Atlas::User'
    validates_uniqueness_of :user_id, :fb_user_id
    attr_accessible :user_id, :fb_user_id
  end
end

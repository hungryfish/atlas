module Atlas
  class UserSource < ActiveRecord::Base
    belongs_to :user
    belongs_to :source
  end
end
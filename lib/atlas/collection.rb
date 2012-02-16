module Atlas
  class Collection < ActiveRecord::Base
    has_many :widget_references, :as => :widget, :class_name => 'Atlas::WidgetReference'
    
    def self.default_title(current_user)
      "Places shared by #{current_user.username} #{Time.now.strftime('on %m/%d/%Y at %I:%M%p')}"
    end
    
    def photos; []; end
    def category; Atlas::Category.find('Uncategorized'); end
  end
end
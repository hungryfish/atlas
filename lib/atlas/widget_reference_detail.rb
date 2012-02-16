module Atlas
  class WidgetReferenceDetail < ActiveRecord::Base
    belongs_to :widget_reference, :class_name => 'Atlas::WidgetReference'
    
    validates_presence_of :widget_reference_id, :url
  end
end

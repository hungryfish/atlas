module Atlas
  class WidgetReference < ActiveRecord::Base
    belongs_to :widget, :polymorphic => true
    has_many :widget_reference_details, :class_name => 'Atlas::WidgetReferenceDetail'
    
    validates_presence_of :widget_id, :widget_type, :referencing_domain, :reference_count
    validates_uniqueness_of :widget_id, :scope => [:widget_type, :referencing_domain]
  end
end

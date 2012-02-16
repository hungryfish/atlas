module Atlas
  module Extensions
    module Source 
      class Booking < ActiveRecord::Base
        set_table_name "bookings"
        belongs_to :source, :class_name => 'Atlas::Source'
      end
    end
  end
end
module PublicEarth
  module Db
    class DeviceQueue < PublicEarth::Db::Base
      class << self
        
        # Retrieve the places in the user's device queue
        def items(user, from_database = false)
          in_queue = user.settings.queue_items

          if from_database
            item_details(in_queue)
          else
            item_details_from_search(in_queue.keys)
          end
        end

        # Add an item(s) to the queue
        # place_ids is a comma-separated list of place id's
        def add(user, place_ids)
          place_ids = place_ids.split(',')

          if place_ids.length > 0
            to_add = Atlas::Place.find(place_ids)
          end

          if user.logged_in?
            to_add.each do |place|
              user.settings.queue_items[place.id] = place.name.to_s
            end
            user.settings.save
          end
        end
        
        # Remove a place from the device queue
        def remove(user, place_id)
          user.settings.queue_items.delete(place_id)
          user.settings.save
        end

        # Empty the device queue
        def clear(user)
          if user.logged_in?
            user.settings.queue_items = {}
            user.settings.save
          end
        end

        private

        # Grab the full place object from the database
        # Use item_details_from_search if you don't need the region/route data
        def item_details(items)
          queue_items = []
          items.each do |id, name|
            queue_items.push(Atlas::Place.find(id))
          end

          queue_items
        end

        # Grab the place objects from the search index
        # This is faster if you don't need _everything_ from the DB.
        def item_details_from_search(ids)
          Atlas::Place.find_from_search(ids)
        end

      end
    end
  end
end

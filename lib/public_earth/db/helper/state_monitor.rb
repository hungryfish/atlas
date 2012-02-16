module PublicEarth
  module Db
    module Helper
      
      # Track the state of the model:  new, exists, updated, deleted.
      module StateMonitor

        # Reset the state of the model, i.e. make everything false.
        def clear_state
          @exists = false
          @deleted = false
          @changed = false
        end
        
        # Has this object been deleted?
        def deleted?
          @deleted
        end

        # Mark this object for deletion.
        def deleted
          @changed = true
          @deleted = true
        end

        # Has this object been modified, and needs to be saved to the database?
        def changed?
          @changed
        end
        alias :updated? :changed?
        
        # Mark this object as having changed somehow.
        def changed
          @deleted = false
          @changed = true
        end
        alias :updated :changed

        # Has this object already been saved to the database, i.e. does it need to be created?
        def exists?
          @exists
        end

        # Mark this object as existing in the database.
        def exists
          @deleted = false
          @exists = true
        end

        # Return what to do with this model in a simple form:  :create, :update, or :delete.  Returns
        # nil if you don't need to do anything to the model, i.e. it isn't new and it hasn't changed
        # or been deleted.
        #
        # You may also send a block to this method that will be passed the state information.  Simply
        # perform you create, update, and delete cases in that block.  If an error occurs, raise an
        # exception to get out of it.  Otherwise, if successful, the state of the model is automatically
        # updated for you based on what state it was in.
        def what_to(&block)
          state = nil
          
          if exists?
            if deleted?
              state = :delete
            elsif changed?
              state = :update
            end
          else
            state = :create
          end
          
          if block
            block.call(state)
            case state
            when :create, :update
              @deleted = false
              @changed = false
              @exists = true
            when :delete
              @deleted = true
              @changed = false
            end
          end
          
          state
        end
      end
    end
  end
end
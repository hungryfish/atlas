module Atlas
  class UserAction < ActiveRecord::Base
    belongs_to :place, :class_name => 'Atlas::Place'
    belongs_to :user, :class_name => 'Atlas::User'

    default_scope :conditions => "not exists(select 1 from deletions where user_actions.place_id = deletions.id)"

    named_scope :grouped_by_hour, :select => "distinct on (date_part(\'year\', user_actions.created_at), date_part(\'month\', user_actions.created_at), date_part(\'day\', user_actions.created_at), user_actions.place_id, action) user_actions.*",
                                  :order => 'date_part(\'year\', user_actions.created_at) desc, date_part(\'month\', user_actions.created_at) desc, date_part(\'day\', user_actions.created_at) desc, user_actions.place_id, action, created_at desc'

    def what_happened
      case action
        when 'create': 'created'
        when 'view': 'viewed'
        when 'edit': 'updated'
        when 'rate': 'rated'
        when 'save': 'saved'
        when 'share': 'shared'
        when 'text to phone': 'shared'
        when 'photo': 'uploaded photo'
        when 'delete': 'deleted'
        when 'undelete': 'undeleted'
        else action
      end
    end
  end
end

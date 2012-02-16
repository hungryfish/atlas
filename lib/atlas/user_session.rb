module Atlas
  class UserSession < ::Authlogic::Session::Base
    authenticate_with Atlas::User
  end
end

# Enable Authlogic to work with our Atlas::User authentication system.
module Atlas
  module Extensions
    module User
      module AuthlogicSupport
        def self.included(included_in)
          included_in.class_eval do
      
            acts_as_authentic do |config|
              config.login_field = :username
              config.email_field = :email
              config.crypto_provider = Authlogic::CryptoProviders::MD5
              config.crypted_password_field = :crypted_password
              config.password_salt_field = nil
              config.session_class = Atlas::UserSession
            end

          end
        end
  
        def crypted_password
          read_attribute :password
        end
  
        def crypted_password=(value)
          write_attribute :password, value
        end
  
        def crypted_password_changed? 
          false
        end
  
      end
    end
  end
end


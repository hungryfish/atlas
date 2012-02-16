$:.unshift(File.dirname(__FILE__)) unless
  $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'public_earth'

module Atlas
  VERSION = '2.3.12'
end

# Require all files in /initializers
Dir.glob(File.join(File.dirname(__FILE__), 'initializers/*.rb')).each {|f| require f }

class Module    

  # Expects a method that will throw an exception if it fails.  Creates a method that wraps this method call in a 
  # try/catch block and returns nil if the request fails.  If no alternate method name is specified for this new
  # method, expects the original method to end in an exclamation point, which it will strip off and use the remaining
  # method name as the alternate name.  For example, +find_by_id!+ becomes +find_by_id+.
  def alias_no_exception(method, alternate = nil)
    alternate = method.to_s.gsub(/\!\Z/, '') unless alternate
    class_eval <<-METHOD
      def #{alternate}(*args)
        begin
          send(:#{method}, *args)
        rescue
          nil
        end
      end
    METHOD
  end

end 
class Array
  
  # Look up an object in an array by its "name" property.   Makes it behave a little like a hash,
  # though not as efficient.
  def named(name)
    detect {|a| a.name.to_s == name}
  end
  
end

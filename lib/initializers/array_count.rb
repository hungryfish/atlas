# For simulated place attribute values, make Array respond to "count" like it's "size" or "length".
class Array
  alias :count :length
end

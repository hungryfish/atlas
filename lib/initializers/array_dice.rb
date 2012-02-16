class Array
  
  # Break an array into an array of smaller arrays.  
  def dice(slice_size = 10)
    results = []
    (self.length / slice_size.to_f).ceil.times do |idx|
      results << self.slice(idx * slice_size, slice_size)
    end
    results
  end
  
end

class Hash
  
  # Remove the given key from the hash.  Returns a cloned hash; does not modify the original.
  def -(value)
    dup = self.clone
    dup.delete(value)
    dup
  end
  
end

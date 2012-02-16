# Each source may be responsible for more than one set of data.  For example, NationalAtlas.gov 
# generates several content sets, such as cities and airports.  
module Atlas
  class SourceDataSet < ActiveRecord::Base
    validates_presence_of :name
  
    belongs_to :source, :class_name => 'Atlas::Source'
    has_many :place_source_data_sets, :class_name => 'Atlas::PlaceSourceDataSet'
    has_many :places, :through => :place_source_data_sets, :class_name => 'Atlas::Place'
  
    def ==(other)
      other.kind_of?(SourceDataSet) && self.id == other.id 
    end
    
    def to_s
      self.name
    end
  end
end
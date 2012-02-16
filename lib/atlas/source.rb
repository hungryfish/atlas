module Atlas
  class Source < ActiveRecord::Base
    extend ActiveSupport::Memoizable
    
    # ANONYMOUS_NAMES = [
    #     'Claudius Ptolemy', 'Martin Waldseemuller', 'Jacopo Gastaldi', 'Antonio Lafreri', 'Sebastian Munster',
    #     'Gerard Mercator', 'Jodocus Hondius', 'Johannes Jansson', 'Willem Blaeu', 'Nicholas Sanson', 'Vincenzo Coronelli',
    #     'Guillaume De L\'Isle', 'Jean Baptiste D\'Anville', 'Jacques Nicholas Bellin', 'John Speed', 'Herman Moll',
    #     'John Mitchell', 'Lewis Evans', 'Thomas Jefferys', 'William Faden', 'Aaron Arrowsmith', 'John Cary', 
    #     'Matthew Carey', 'Jedidiah Morse', 'John Melish', 'Henry Tanner', 'Rand, McNally', 'Joseph H. Colton'
    #   ]
    ANONYMOUS_NAMES = ['ClaudiusPtolemy', 'MartinWaldseemuller', 'JacopoGastaldi', 'AntonioLafreri', 'SebastianMunster', 
        'GerardMercator', 'JodocusHondius', 'JohannesJansson', 'WillemBlaeu', 'NicholasSanson', 'VincenzoCoronelli', 
        'GuillaumeDeLIsle', 'JeanBaptisteDAnville', 'JacquesNicholasBellin', 'JohnSpeed', 'HermanMoll', 'JohnMitchell', 
        'LewisEvans', 'ThomasJefferys', 'WilliamFaden', 'AaronArrowsmith', 'JohnCary', 'MatthewCarey', 'JedidiahMorse', 
        'JohnMelish', 'HenryTanner', 'JosephHColton']
    
    validates_presence_of :name
  
    has_many :source_data_sets, :class_name => 'Atlas::SourceDataSet'
    has_many :contributions, :class_name => 'Atlas::Contribution'
    has_many :contributors, :class_name => 'Atlas::Contribution'
    
    has_many :modified_places, :class_name => 'Atlas::Place', :through => :contributions, :source => :place, :conditions => {"contributors.creator" => false}
    has_many :created_places, :class_name => 'Atlas::Place', :through => :contributions, :source => :place, :conditions => {"contributors.creator" => true}
    has_many :created_or_modified_places, :class_name => 'Atlas::Place', :through => :contributions, :source => :place
    
    has_many :ratings, :class_name => 'Atlas::Rating'
    has_many :rated_places, :through => :ratings,  :source => :place, :class_name => 'Atlas::Place'
    
    has_one :user_source, :class_name => 'Atlas::UserSource'
    has_one :user, :through => :user_source, :class_name => 'Atlas::User'

    has_one :booking, :class_name => 'Atlas::Extensions::Source::Booking'

    has_one :featured, :as => :featureable, :class_name => "Atlas::Featured"
    named_scope :partners, :conditions => "icon_path IS NOT NULL"
    
    # Look up or create a mobile user, for the API.  Similar to .create, but the name is created as "Mobile User" with a 
    # number after it.  The URI will be mobile://<remote_id>.
    def self.mobile(remote_id)
      remote_id = remote_id.gsub(/[^\w\-\.\@]+/, '')
      existing = find :first, :conditions => "uri = 'mobile://#{remote_id}'"
      
      if existing.blank?
        transaction do
          max_num = connection.select_value("
            select regexp_replace(name, E'Mobile User(?:\\\\s*#(\\\\d*))?', E'0\\\\1')::integer + 1 as max_num from sources 
              where name ~ ('Mobile User' || E'(?:\\\\s*#(\\\\d*))?') order by max_num desc limit 1
              for update")
          existing = create :name => "Mobile User ##{max_num.to_i}", :uri => "mobile://#{remote_id}"
        end
      end

      existing
    end

    def user?
      user.present?
    end
    
    def visible_for?(place)
      if place
        contribution = Atlas::Contribution.find :first, :conditions => {:source_id => self, :place_id => place }
        contribution && contribution.publicly_visible?
      else
        true
      end
    end
    
    def anonymous_user?
      uri =~ /^anonymous\:\/\// && true || false
    end
    
    # Creates a new source data set for this source.  
    #
    # Note that the Atlas::User also has this method, but it always returns the same source data set.
    # This reflects the business rule:  a user always has a single source data set, while partners get
    # a new set with every data load.
    #
    # Only creates one per session, and memoizes it.
    def source_data_set(options = {})
      source_data_sets.create(options.reverse_merge(:name => "Source data set for #{name}"))
    end
    memoize :source_data_set
    
    # So we can mimic the User class, i.e. @contributing.source is the same if @contributing is either a
    # user or a source.
    def source
      self
    end
    
    # Pass in the place to check if it's visible for this account.
    def to_s(place = nil)
      (user? && user.username) || 
      (anonymous_user? && self.random_name) || 
      (visible_for?(place) && self.name) || 
      self.random_name
    end

    def self.random_name
      ANONYMOUS_NAMES[rand(ANONYMOUS_NAMES.length)]
    end
    
    def random_name
      'Anonymous' #Atlas::Source.random_name      
    end
    
    def to_hash
      hash = {
        :id => self.id,
        :name => to_s,
        :uri => self.uri,
        :copyright => self[:copyright],
        :icon => self[:icon]
      }
      hash[:user] = self.user.to_hash if self.user
      hash
    end
    
    def to_json(*a)
      to_hash.to_json(*a)
    end
    
    def to_xml
      xml = XML::Node.new('source')
      xml['id'] = self.id

      xml << xml_value(:name, to_s)
      xml << xml_value(:uri, self[:uri])
      xml << xml_value(:copyright, self[:copyright])
      xml << xml_value(:icon, self[:icon])
      
      xml << user.to_xml if user
      
      xml
    end
  
  end
end
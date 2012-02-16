require 'ostruct'

module PublicEarth
  module Search

    @servers = nil
    
    class << self
      def config
        if @servers.nil? || RAILS_ENV == 'development'
          if File.exist? "#{RAILS_ROOT}/config/search.yml" 
            @servers = YAML.load_file("#{RAILS_ROOT}/config/search.yml")[RAILS_ENV]
            if @servers
              @servers.keys.each do |name|
                @servers[name].reverse_merge!('context' => name)
                @servers[name] = PublicEarth::Search::Solr.new @servers[name]
              end
            end
          end
        end

        @servers ||= {
              $default_solr_index => PublicEarth::Search::Solr.new(:context => $default_solr_index)
            }
      end
  
      def servers
        config
      end
    end
    
    class SearchFailed < StandardError; end
    class InvalidRequest < StandardError; end
    class ConnectionFailed < StandardError; end
  
    module Extensions
      module Searchable
        # Indicate the module is searchable.  For example:
        #
        #  class MyModel < ActiveRecord::Base
        #    is_searchable
        #  end
        #
        def is_searchable
          self.class_eval do
            extend PublicEarth::Search::Extensions::SolrModelClassMethods
            include PublicEarth::Search::Extensions::SolrModelInstanceMethods
          end
        end
      end

      module SolrModelClassMethods
      
        # Indicate the Solr index for this model, via the key in the search.yml file.  Defaults 
        # to "solr".  Your application may override this default in its configuration, via 
        # $default_solr_index value.
        #
        #  class MyModel < PublicEarth::Db::Base
        #    is_searchable
        #    set_solr_index 'other index'
        #  end
        #
        # Also override the search_document method to generate your Solr document.
        def set_solr_index(index = $default_solr_index)

          # Get the class object for the model you're calling this from.  Neat trick...
          parent = class << self; self; end

          # Adjust the class object itself, i.e. def solr_server is more like def self.solr_server.
          parent.send(:alias_method, 'default_solr_server', 'solr_server')
          parent.class_eval "def solr_server; PublicEarth::Search::servers['#{index}']; end"
        end
        alias :solr_index= :set_solr_index
        alias :solr_server= :set_solr_index

        # A reference to the Solr server this model is using.  Returns the default server.  If
        # set_solr_index is used (or one of its aliases), this method is renamed to 
        # "default_solr_server".
        def solr_server
          PublicEarth::Search::servers[$default_solr_index]
        end

        # Query the Solr server.
        def search_for(keywords, options = {})
          solr_server.find(keywords, options)
        end
        
        # Add multiple documents to Solr at once.  It's more efficient to send them en masse.  You
        # can build up the list with something like:
        def many_to_solr(searchable_objects)
          outgoing = StringIO.new('', 'w')
          outgoing.printf('<add>')
          searchable_objects.each { |searchable_object| searchable_object.search_document_xml(outgoing) }
          outgoing.printf('</add>')

          begin
            solr_server.post outgoing.string
          rescue 
            logger.error("Failed to index places: #{$!}")
            return false
          end
        end
        
        # Forcibly reindex all the model objects currently in the database into the search
        # indexes.  Waits until the end to commit everything, so you may not see documents in 
        # your index right away.
        #
        # To use this method, your class must define a "find_all" method, which can be dangerous
        # if you have more than a few hundred thousand records!
        def reindex_all
          find_all.each {|model| model.reindex(false)}
          solr_server.commit
          solr_server.optimize
        end
      end
    
      module SolrModelInstanceMethods

        # You should override this and return a hash document for Solr.
        def search_document
          nil
        end

        def escapeXML(unescaped)
          unescaped.to_s.gsub(/&/, '&amp;').gsub(/</, '&lt;').gsub(/>/, '&gt;')
        end
        
        # Attach this place to the given XML Builder.  For sending a number of documents to the server
        # at once.
        def search_document_xml(builder)
          builder.printf('<doc boost="%.2f">', (boost || 1.0))
          search_document.each do |key, value|
            (value.kind_of?(Array) && value || [value]).each do |value|
              builder.printf('<field name="%s">%s</field>', escapeXML(key), escapeXML(value)) unless value.blank?
            end
          end
          builder.printf("</doc>")
        end
        
        # Convenience method to return the Solr server reference from the object instance
        # itself.  Just like calling Model.solr_server.
        def solr_server
          self.class.solr_server
        end
      
        # Use XML Builder to create an XML document, based on the search_document.
        # TODO:  Would it be faster to use RXML?  These are small documents, so it might not matter...
        def solr_xml
          outgoing = StringIO.new('', 'w')
          outgoing.printf('<add>')
          search_document_xml(outgoing)
          outgoing.printf('</add>')
          outgoing.string
        end

        # Send the Solr document (from the search_document method) to Solr.  If your object does not have
        # a search_document method, the reindex request will be ignored.  Set autocommit to false if you're
        # reindexing a bunch of models at once for better performance.
        def reindex(autocommit = true)
          if search_document
            logger.debug("Updating #{self.class} #{self.id} in the search indexes.")
            begin
              solr_server.post solr_xml
              solr_server.commit if autocommit
            rescue 
              puts $!
              logger.error("Failed to index #{self.class} #{self.id} at #{Time.new}: #{$!}")
              return false
            end
          end
        end
      
        # Delete this object from the search index.
        def remove_from_index(autocommit = true)
          if search_document
            logger.debug("Removing #{self.class} #{self.id} from the search indexes.")
            begin
              solr_server.delete(search_document[:id])
              solr_server.commit if autocommit
            rescue
              logger.error("Failed to remove #{self.class} #{self.id} from index at #{Time.new}: #{$!}")
              return false
            end
          end
        end

        # Try to find additional objects similar to this one in the search engine.
        def more_like_me(options = {})
          solr_server.more_like_this(self.id, options)
        end
      end
    end

    # Any PublicEarth "model" may be made searchable by calling "is_searchable" and defining a 
    # search_document method.
    PublicEarth::Db::Base.send :extend, PublicEarth::Search::Extensions::Searchable

    # ActiveRecord models may also be searchable
    ActiveRecord::Base.send :extend, PublicEarth::Search::Extensions::Searchable
  end
end

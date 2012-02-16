require 'ostruct'
require 'net/http'
require 'cgi'

module PublicEarth
  module Search
    
    # Handles interaction with the Solr server.
    class Solr
  
      cattr_accessor :logger, :instance_writer => false
      attr_accessor :context_path, :server, :default_query, :master 
  
      VALID_SOLR_PARAMETERS = %w(q qt wt sort start rows fq fl debugQuery explainOther defType timeAllowed omitHeader facet facets hl mlt)
      
      # Indicate the context (path) on the Solr server to use for this search.  Possible 
      # parameters:
      #
      # context:: the Solr search index to use; defaults to 'solr'
      # host:: the full URL, including http:// and port number (if not 80), to the server;
      #        defaults to http://localhost
      # default:: the default results handler to use on the server, as it is named in the 
      #           solrconfig.xml; defaults to 'standard', which is the Solr default
      # master:: the master Solr search server; defaults to the same as "host"
      #
      def initialize(params = {})
        begin
          @context_path = params['context'] || 'solr'
          @server = URI.parse(params['host'] || 'http://localhost')
          @default_query = params['default'] || 'standard'
          @master = URI.parse(params['master'] || params['host'] || 'http://localhost')
        rescue
          logger.error $!
          raise "Unable to configure Solr server connection.  Maybe a bad or missing server URL:  #{server}."
        end
      end

      # Search the Solr server for the given keywords (and standard Lucene options), and
      # return the response hash.  The hash will contain 'docs', 'numFound', etc.
      # 
      # Raises a SearchFailed exception if unable to find the response object or the server
      # fails to respond.
      #
      # Provides a simple way to indicate a facets filter:  simply pass :facets => 'field'.  
      # Defaults to returning no more than 25 facets, which you can override with :'facet.limit'.
      #
      # For example, to filter by 10 tags, find(keywords, :facets => 'tag', :'facet.limit' => 10).
      def find(keywords, options = {})
        results_class = options.delete(:results) || PublicEarth::Search::Solr::Results
        results_class.new query_server(keywords, options)
      end

      # The raw call to the Solr server.  Returns the JSON response.  Same documentation as for the
      # find method, just unfiltered results.
      def query_server(keywords, options = {})
        if options.has_key? :facets
          options.reverse_merge!({
            :facet => true,
            :'facet.field' => options[:facets],
            :'facet.sort' => true,
            :'facet.mincount' => 1,
            :'facet.limit' => 25
          })
          options.delete :facets
        end
        
        if options.has_key? :highlight
          options.reverse_merge!({
            :hl => 'on',
            :'hl.fl' => options.delete(:highlight)
          })
        end
        
        if options.has_key? :fields
          options.reverse_merge!({ :fl => options[:fields] })
          options.delete :fields
        end
        
        options.reverse_merge!(:q => keywords, :wt => 'ruby')
        
        # Filter out any unsupported options for the search engine; seems to affect performance with Solr.
        options.delete_if { |key, value| !VALID_SOLR_PARAMETERS.include?(key.to_s.gsub(/\..*/, '')) || value.nil? }
        
        self.get(options)
      end
      
      # Runs a search against the Solr server for additional results that look like this one.
      def more_like_this(id, options = {})
        options.reverse_merge!({
          :q => "id:#{id}",
          :mlt => true,
          :'mlt.fl' => options[:similarities],
          :'mlt.mindf' => 1,
          :'mlt.mintf' => 1,
          :fl => '*,score',
          :qt => 'standard',
          :wt => 'ruby'
        })
        options.delete :similarities
        
        self.get(options)
      end
      
      # Post some XML to the Solr server, typically a command or a document to index.
      # Returns the XML returned from the server.
      def post(document, action = 'update')
        return unless @master
        begin
          post = Net::HTTP::Post.new("/#{@context_path}/#{action}")
          post.body = document
          post.content_type = 'text/xml'

          response = Net::HTTP.start(@master.host, @master.port) do |http|
            http.request(post)
          end
          raise PublicEarth::Search::SearchFailed, "Solr failed to respond to your request: #{document}\n\n#{response.body}" if response.body =~ /^<html>/

          return response.body
        rescue PublicEarth::Search::SearchFailed
          raise
        rescue SyntaxError
          raise PublicEarth::Search::InvalidRequest, "Solr could not process your query: #{parameters}"
        rescue Exception
          raise PublicEarth::Search::ConnectionFailed, "Unable to contact the Solr server (#{@master}/#{@context_path}): #{$!})"
        end
      end

      # Post some XML to the Solr server, typically a command or a document to index.
      # Returns the XML returned from the server.
      def get(parameters = {}, action = 'select')
        begin
          url = "/#{@context_path}/#{action}?"
          parameters.reverse_merge!(:qt => @default_query)
          parameters.each do |parameter, value|
            url += "#{CGI.escape(parameter.to_s)}=#{CGI.escape(value.to_s)}&"
          end
          url.gsub! /&$/, ''
      
          http = Net::HTTP.new(@server.host, @server.port)
          response, data = http.get(url)
          raise PublicEarth::Search::SearchFailed, "Solr failed to respond to your request: \n\n#{response.body}." if data =~ /^<html>/

          data.gsub! /rating_count(\d+)average_rating([\d.]+)/, '\2'
          return eval(data)
        rescue PublicEarth::Search::SearchFailed
          raise
        rescue SyntaxError
          raise PublicEarth::Search::InvalidRequest, "Solr could not process your query: #{parameters.inspect}, url = #{url}"
        # rescue Exception
        #   raise PublicEarth::Search::ConnectionFailed, "Unable to contact the Solr server (#{@server}/#{@context_path}): #{$!})"
        end
      end

      # Delete the given document (by ID) from the Solr search index.
      def delete(id, autocommit = true)
        self.post("<delete><id>#{id}</id></delete>")
        self.commit if autocommit
      end

      # Force a commit of any changes you've made to Solr.
      def commit
        begin
          self.post('<commit/>')
        rescue
          logger.warn("Unable to contact the Solr server (#{@server}/#{@context_path}): #{$!}
           \n\n Changes will be commited automatically by the server shortly.")
        end
      end

      # Optimize the search indexes.  This should be done now and again to improve search 
      # performance.
      def optimize
        begin
          self.post('<optimize/>')
        rescue
          logger.warn("Error with the Solr server (#{@server}/#{@context_path}): #{$!}")
        end
      end
      
      def ping
        self.post('<pingQuery>q=solr&amp;version=2.0&amp;start=0&amp;rows=0</pingQuery>')
      end
  
      # Simplify the results hash that comes back from Solr.  Returns the number of results in
      # .found, and the documents found in .documents.  If no results are found for the query, 
      # .found will be 0.  If you have results, but you've paged past them, you'll get an empty
      # .documents array.
      class Results

        def initialize(solr_results = {})
          @query = solr_results['params']['q'] rescue nil
          
          response = solr_results['response']
          if response
            @max_score = response['maxScore'] &&  response['maxScore'].to_f || 0
            @found = response['numFound'] && response['numFound'].to_i || 0
            @documents = response['docs']
            @highlights = solr_results['highlighting']
            @facets =  solr_results['facet_counts'] && solr_results['facet_counts']['facet_fields'] || {}
            @start = response['start'] && response['start'].to_i || 0
          else
            @max_score = 0
            @found = 0
            @documents = []
            @facets = {}
            @highlights = {}
            @start = 0
            @spelling
          end

          # Correct bad spelling?
          @speling = solr_results['spellcheck'] && solr_results['spellcheck']['suggestions']
        end

        def query
          @query
        end
        
        # The highest Solr relevance score returned by the search.
        def max_score
          @max_score
        end

        # The total number of documents that could be returned by the query.
        def found
          @found
        end
        alias :count :found

        def start
          @start
        end

        # The array of documents returned by the query, in the requested sort order.
        def documents
          @documents
        end

        def documents=(value)
          @documents = value
        end

        def speling_suggestions
          @speling
        end

        def suggested_spelling
          (@speling.dice(2).map { |a| a.last['suggestion'].join(' ') }).join(' ')
        end

        # If you filter on a field, such as "tag", "sector", "industry", "stock_exchange", this
        # holds the hash of counts by facet.  You can pass in the facet name to get the ordered
        # pairs, e.g. [['Microsoft', 17], ['Apple', 25], ['Vista', 3]]
        def facets(facet_name = nil)
          if facet_name
            facets = []
            (@facets[facet_name].length / 2).times {|i| facets << [@facets[facet_name][i * 2], @facets[facet_name][i * 2 + 1]]}
            facets
          else
            @facets
          end
        end

        def highlights
          @highlights
        end
        
        # Return the documents as mock models using OpenStruct.  Note that these are NOT the
        # original models!  This is a basic, no-frills convenience method that works in the
        # simple cases, such as for rendering partials.  If there are discrepancies between
        # your database model and your search document schema, this probably won't work.
        #
        # Also has the side effect that if you have a "name" column in your schema, this will
        # add it as a to_s method to your model.
        def models
          @models ||= documents.map do |doc| 
            model = OpenStruct.new doc 
            model.instance_eval { alias :to_s :name } if doc.has_key? 'name'
            model
          end
        end

        # TODO:  Incorporate Enumerable instead of manually doing this...

        # Loop over each document and yield the given block
        def each(&block)
          @documents.each &block
        end

        def each_with_index(&block)
          @documents.each_with_index &block
        end
        
        def present?
          @documents.present?
        end
        
        def blank?
          @documents.blank?
        end
      end
    end
    
    class SearchFailed < StandardError; end
    class InvalidRequest < StandardError; end
    class ConnectionFailed < StandardError; end
    
  end
end


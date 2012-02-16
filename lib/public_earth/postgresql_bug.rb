require 'active_record/connection_adapters/postgresql_adapter'

# Fix PostgreSQL bug that doesn't handle schema names correctly.
module FixedQuoting  
  
  # This is broken in the Rails 2.1.0 PostgreSQL adapter.  Doesn't take schema names into account.
  # This method fixes this...
  def quote_table_name(table_name)
    (table_name.split(/\./, 2).map { |piece| %("#{piece}") }).join('.')
  end
  
end

ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.send(:include, FixedQuoting)


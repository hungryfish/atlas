require 'active_record/connection_adapters/abstract/schema_statements'

module ActiveRecord
  module ConnectionAdapters # :nodoc:
    module SchemaStatements
      
      # Add the option to generate GUIDs for the table ID to the create_table migration statement.
      #
      #   create_table :id => :guid do |t|
      #
      def create_table_with_guids(table_name, options = {}, &block)
        if options[:id] == :guid || options[:id] == :uuid
          options[:id] = false
          create_table_without_guids(table_name, options) do |t|
            t.string :id, :limit => 40, :null => false
            block.call t
          end
          execute "alter table #{quote_table_name(table_name)} add primary key (id)"
          execute "alter table #{quote_table_name(table_name)} alter column id set default generate_uuid()"
        else
          create_table_without_guids(table_name, options, &block)
        end
      end
      alias_method_chain :create_table, :guids

    end
  end
end
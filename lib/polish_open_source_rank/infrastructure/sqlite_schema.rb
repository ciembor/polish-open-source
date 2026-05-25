# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    module SQLiteSchema
      module_function

      def sql
        @sql ||= schema_path.read
      end

      def schema_path
        PolishOpenSourceRank.root.join('lib/polish_open_source_rank/infrastructure/sqlite_schema.sql')
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Opens the mutable and public read-only SQLite connections required by web adapters.
      class Persistence
        def initialize(configuration:)
          @configuration = configuration
        end

        def database
          @database ||= begin
            db = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
            Infrastructure::PlatformSchemaMigration.new(db, Infrastructure::SQLiteSchema.sql).bootstrap!
            db
          end
        end

        def public_database
          public_path = configuration.public_database_path
          return database if public_path == configuration.database_path

          @public_database ||= Shared::Infrastructure::SQLite::Database.open(
            public_path,
            readonly: true
          )
        end

        private

        attr_reader :configuration
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Owns filesystem and edge-cache side effects that surround a successful snapshot publication.
          class SQLitePublicSnapshotPublicationEffects
            def initialize(database, backup_root: nil, public_cache_purger: nil, public_database_path: nil)
              @database = database
              @backup_root = backup_root
              @public_cache_purger = public_cache_purger
              @public_database_path = public_database_path
            end

            def checkpoint_and_backup(period_start)
              database.execute('PRAGMA wal_checkpoint(TRUNCATE)')
              return unless backup_root

              FileUtils.mkdir_p(backup_root)
              backup_path = File.join(backup_root, "public-#{period_start}.sqlite3")
              FileUtils.cp(database.path, backup_path)
              backup_path
            end

            def refresh_public_database_snapshot
              public_database_snapshot&.refresh
            end

            def purge_public_cache
              public_cache_purger&.purge_public_cache
            end

            private

            attr_reader :backup_root, :database, :public_cache_purger, :public_database_path

            def public_database_snapshot
              return if public_database_path.to_s.empty? || public_database_path == database.path

              @public_database_snapshot ||= SQLitePublicDatabaseSnapshot.new(
                source_database: database,
                path: public_database_path
              )
            end
          end
        end
      end
    end
  end
end

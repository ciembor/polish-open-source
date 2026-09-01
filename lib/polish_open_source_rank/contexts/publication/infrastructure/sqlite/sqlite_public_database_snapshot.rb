# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Builds an atomically replaced SQLite file for read-only public web traffic.
          class SQLitePublicDatabaseSnapshot
            # Raised when the temporary SQLite copy is not safe to expose as the public database.
            class VerificationFailed < StandardError; end

            def initialize(source_database:, path:)
              @source_database = source_database
              @path = Pathname(path)
            end

            def refresh
              snapshot_path = path.to_s
              return if snapshot_path.empty? || snapshot_path == source_database.path

              source_database.execute('PRAGMA wal_checkpoint(TRUNCATE)')
              FileUtils.mkdir_p(path.dirname)
              copy_to_temporary_snapshot
              verify_temporary_snapshot
              File.rename(temporary_path, path)
              snapshot_path
            ensure
              FileUtils.rm_f(@temporary_path) if @temporary_path
            end

            private

            attr_reader :path, :source_database

            def copy_to_temporary_snapshot
              FileUtils.cp(source_database.path, temporary_path)
            end

            def verify_temporary_snapshot
              database = Shared::Infrastructure::SQLite::Database.open(temporary_path, readonly: true)
              result = database.fetch_value('PRAGMA integrity_check')
              raise VerificationFailed, result unless result == 'ok'
            ensure
              database&.close
            end

            def temporary_path
              @temporary_path ||= path.sub_ext("#{path.extname}.tmp-#{Process.pid}")
            end
          end
        end
      end
    end
  end
end

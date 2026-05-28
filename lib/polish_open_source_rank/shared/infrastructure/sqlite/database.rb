# frozen_string_literal: true

require 'sequel'

module PolishOpenSourceRank
  module Shared
    module Infrastructure
      module SQLite
        class Database
          SQLITE_WRITE_RETRIES = 3
          SQLITE_WRITE_RETRY_DELAY = 0.25
          SQLITE_LOCK_MESSAGES = [
            /database is locked/i,
            /database table is locked/i,
            /database schema is locked/i
          ].freeze

          def self.open(path)
            new(path).open
          end

          def initialize(path)
            @path = Pathname(path)
          end

          def open
            FileUtils.mkdir_p(path.dirname)
            connect
            self
          end

          def close
            @sequel_connection&.disconnect
            @sequel_connection = nil
          end

          def execute(sql, params = [])
            sequel_connection.fetch(sql, *params).delete
          end

          def execute_batch(sql)
            raw_connection.execute_batch(sql)
          end

          def fetch_all(sql, params = [])
            sequel_connection.fetch(sql, *params).all
          end

          def fetch_value(sql, params = [])
            sequel_connection.fetch(sql, *params).single_value
          end

          def table_info(table_name)
            with_hash_results { raw_connection.table_info(table_name) }
          end

          def dataset(table_name)
            sequel_connection[table_name.to_sym]
          end

          def transaction(&)
            with_sqlite_write_retry do
              sequel_connection.transaction(mode: :immediate, &)
            end
          end

          private

          attr_reader :path

          def connect
            sequel_connection
          end

          def raw_connection
            sequel_connection.synchronize do |connection|
              return connection
            end
          end

          def sequel_connection
            @sequel_connection ||= Sequel.connect(
              "sqlite://#{path}",
              max_connections: 1,
              after_connect: method(:configure_connection)
            )
          end

          def configure_connection(connection)
            connection.busy_timeout = 120_000
            connection.execute('PRAGMA foreign_keys = ON')
            connection.execute('PRAGMA journal_mode = WAL')
            connection.execute('PRAGMA synchronous = NORMAL')
          end

          def with_sqlite_write_retry
            attempts = 0

            begin
              yield
            rescue Sequel::DatabaseError => e
              attempts += 1
              raise unless sqlite_lock_error?(e) && attempts <= SQLITE_WRITE_RETRIES

              sleep(SQLITE_WRITE_RETRY_DELAY * attempts)
              retry
            end
          end

          def sqlite_lock_error?(error)
            SQLITE_LOCK_MESSAGES.any? { |pattern| error.message.match?(pattern) }
          end

          def with_hash_results
            raw_connection.results_as_hash = true
            yield
          ensure
            raw_connection.results_as_hash = false
          end
        end
      end
    end
  end
end

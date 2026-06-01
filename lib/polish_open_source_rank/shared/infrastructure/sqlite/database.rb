# frozen_string_literal: true

require 'sequel'

module PolishOpenSourceRank
  module Shared
    module Infrastructure
      module SQLite
        class Database
          DEFAULT_MAX_CONNECTIONS = 8
          SQLITE_WRITE_RETRIES = 8
          SQLITE_WRITE_RETRY_DELAY = 0.25
          SQLITE_LOCK_MESSAGES = [
            /database is locked/i,
            /database table is locked/i,
            /database schema is locked/i
          ].freeze

          @sqlite_write_retry_count = 0

          class << self
            attr_accessor :sqlite_write_retry_count
          end

          def self.open(path, readonly: false)
            new(path, readonly: readonly).open
          end

          def initialize(path, readonly: false)
            @path = Pathname(path)
            @readonly = readonly
          end

          def open
            FileUtils.mkdir_p(@path.dirname) unless readonly
            connect
            self
          end

          def path = @path.to_s

          def close
            @sequel_connection&.disconnect
            @sequel_connection = nil
          end

          def execute(sql, params = [])
            with_sqlite_write_retry { sequel_connection.fetch(sql, *params).delete }
          end

          def execute_batch(sql)
            with_sqlite_write_retry { raw_connection.execute_batch(sql) }
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

          def write(&)
            with_sqlite_write_retry(&)
          end

          private

          attr_reader :readonly

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
              "sqlite://#{@path}",
              max_connections: sqlite_max_connections,
              after_connect: method(:configure_connection)
            )
          end

          def sqlite_max_connections
            Integer(ENV.fetch('SQLITE_MAX_CONNECTIONS', DEFAULT_MAX_CONNECTIONS))
          end

          def configure_connection(connection)
            connection.busy_timeout = 120_000
            connection.execute('PRAGMA query_only = ON') if readonly
            return if readonly

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

              self.class.sqlite_write_retry_count += 1
              sleep(SQLITE_WRITE_RETRY_DELAY * (2**(attempts - 1)))
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

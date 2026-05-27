# frozen_string_literal: true

require 'sequel'

module PolishOpenSourceRank
  module Shared
    module Infrastructure
      module SQLite
        class Database
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
            sequel_connection.transaction(mode: :immediate, &)
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

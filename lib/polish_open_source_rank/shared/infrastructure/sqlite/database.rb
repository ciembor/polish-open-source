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

          def execute(sql, params = [])
            raw_connection.execute(sql, params)
          end

          def execute_batch(sql)
            raw_connection.execute_batch(sql)
          end

          def fetch_all(sql, params = [])
            with_hash_results { execute(sql, params) }.map { |row| symbolize(row) }
          end

          def fetch_value(sql, params = [])
            get_first_value(sql, params)
          end

          def get_first_value(sql, params = [])
            raw_connection.get_first_value(sql, params)
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
              after_connect: method(:configure_connection)
            )
          end

          def configure_connection(connection)
            connection.busy_timeout = 120_000
            connection.execute('PRAGMA foreign_keys = ON')
          end

          def with_hash_results
            raw_connection.results_as_hash = true
            yield
          ensure
            raw_connection.results_as_hash = false
          end

          def symbolize(row)
            row.each_with_object({}) do |(key, value), result|
              result[key.to_sym] = value unless key.is_a?(Integer)
            end
          end
        end
      end
    end
  end
end

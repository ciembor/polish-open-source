# frozen_string_literal: true

require 'sqlite3'

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
            configure_connection
            self
          end

          def execute(sql, params = [])
            connection.execute(sql, params)
          end

          def execute_batch(sql)
            connection.execute_batch(sql)
          end

          def fetch_all(sql, params = [])
            execute(sql, params).map { |row| symbolize(row) }
          end

          def fetch_value(sql, params = [])
            get_first_value(sql, params)
          end

          def get_first_value(sql, params = [])
            connection.get_first_value(sql, params)
          end

          def table_info(table_name)
            connection.table_info(table_name)
          end

          def transaction
            execute('BEGIN IMMEDIATE')
            yield
            execute('COMMIT')
          rescue StandardError
            execute('ROLLBACK')
            raise
          end

          private

          attr_reader :path

          def connection
            @connection ||= SQLite3::Database.new(path.to_s)
          end

          def configure_connection
            connection.results_as_hash = true
            connection.busy_timeout = 120_000
            connection.execute('PRAGMA foreign_keys = ON')
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

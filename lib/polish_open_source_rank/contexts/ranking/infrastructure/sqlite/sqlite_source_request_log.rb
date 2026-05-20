# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSourceRequestLog
            INSERT_SQL = 'INSERT INTO api_request_events(platform, path, status, recorded_at) VALUES (?, ?, ?, ?)'

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record_api_request(platform:, path:, status:, recorded_at: clock.call)
              database.execute(INSERT_SQL, [platform, path, status, recorded_at.iso8601])
            end

            private

            attr_reader :clock, :database
          end
        end
      end
    end
  end
end

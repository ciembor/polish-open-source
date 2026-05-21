# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSourceRequestLog
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record_api_request(platform:, path:, status:, recorded_at: clock.call)
              events_dataset.insert(
                platform: platform,
                path: path,
                status: status,
                recorded_at: recorded_at.iso8601
              )
            end

            private

            attr_reader :clock, :database

            def events_dataset
              database.dataset(:api_request_events)
            end
          end
        end
      end
    end
  end
end

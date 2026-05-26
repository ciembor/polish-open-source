# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLiteMonthlySnapshotCompletion
            def initialize(database)
              @database = database
            end

            def complete?(period)
              database.dataset(:sync_runs)
                      .where(period_start: period.start_date.to_s, status: 'finished')
                      .any?
            end

            private

            attr_reader :database
          end
        end
      end
    end
  end
end

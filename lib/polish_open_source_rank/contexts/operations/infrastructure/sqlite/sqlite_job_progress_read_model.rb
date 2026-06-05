# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLiteJobProgressReadModel < SQLiteJobProgress
            def job_progress(now: Time.now.utc)
              call(now: now)
            end
          end
        end
      end
    end
  end
end

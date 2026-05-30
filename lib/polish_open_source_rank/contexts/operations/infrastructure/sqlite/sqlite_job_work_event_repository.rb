# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLiteJobWorkEventRepository
            include PolishOpenSourceRank::Contexts::Operations::Application::TimedJobWorkEvents

            SQLITE_LOCK_MESSAGES = [
              /database is locked/i,
              /database table is locked/i,
              /database schema is locked/i
            ].freeze

            def initialize(database, heartbeat: nil)
              @database = database
              @heartbeat = heartbeat
            end

            def record(**attributes)
              database.transaction { job_work_events.insert(row(attributes)) }
            rescue Sequel::DatabaseError => e
              raise unless sqlite_lock_error?(e)
            end

            private

            attr_reader :database, :heartbeat

            def row(attributes)
              {
                job_run_id: attributes[:job_run_id],
                period_start: attributes.fetch(:period_start),
                job_kind: attributes.fetch(:job_kind),
                stage: attributes.fetch(:stage),
                unit_kind: attributes.fetch(:unit_kind),
                platform: attributes[:platform],
                ecosystem: attributes[:ecosystem],
                subject_id: attributes[:subject_id]&.to_s,
                subject_label: attributes[:subject_label],
                status: attributes.fetch(:status),
                started_at: attributes.fetch(:started_at),
                finished_at: attributes.fetch(:finished_at),
                duration_ms: attributes.fetch(:duration_ms).to_i,
                error: attributes[:error]
              }
            end

            def job_work_events
              database.dataset(:job_work_events)
            end

            def sqlite_lock_error?(error)
              SQLITE_LOCK_MESSAGES.any? { |pattern| error.message.match?(pattern) }
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLiteJobWorkEventRepository
            include PolishOpenSourceRank::Contexts::Operations::Application::TimedJobWorkEvents

            def initialize(database)
              @database = database
            end

            def record(**attributes)
              database.transaction { job_work_events.insert(row(attributes)) }
            end

            private

            attr_reader :database

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
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Operations
      module Infrastructure
        module SQLite
          class SQLiteCrawlJobRepository
            RESUMABLE_STATUSES = %w[running interrupted].freeze

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def start(command:, arguments:)
              arguments_json = JSON.generate(arguments)
              existing_job = unfinished_job(command, arguments_json)
              return reopen(existing_job) if existing_job

              crawl_job_runs_dataset.insert(
                command: command,
                arguments_json: arguments_json,
                status: 'running',
                attempts: 1,
                started_at: timestamp,
                updated_at: timestamp
              )
            end

            def finish(job_id)
              update(job_id, status: 'finished', finished_at: timestamp, error: nil)
            end

            def fail(job_id, error, status: 'failed')
              update(job_id, status: status, finished_at: timestamp, error: error)
            end

            def retry(job_id, error)
              crawl_job_runs_dataset
                .where(id: job_id)
                .update(
                  attempts: Sequel[:attempts] + 1,
                  error: error,
                  updated_at: timestamp
                )
            end

            def resumable(command: nil)
              dataset = crawl_job_runs_dataset.where(status: RESUMABLE_STATUSES)
              dataset = dataset.where(command: command) if command
              dataset.order(Sequel.asc(:id)).all.map { |job| hydrate(job) }
            end

            def all
              crawl_job_runs_dataset.order(Sequel.desc(:id)).all.map { |job| hydrate(job) }
            end

            private

            attr_reader :clock, :database

            def crawl_job_runs_dataset
              database.dataset(:crawl_job_runs)
            end

            def reopen(job)
              crawl_job_runs_dataset.where(id: job.fetch(:id)).update(
                status: 'running',
                attempts: job.fetch(:attempts).to_i + 1,
                started_at: timestamp,
                finished_at: nil,
                error: nil,
                updated_at: timestamp
              )
              job.fetch(:id)
            end

            def unfinished_job(command, arguments_json)
              crawl_job_runs_dataset
                .where(command: command, arguments_json: arguments_json)
                .exclude(status: 'finished')
                .order(Sequel.desc(:id))
                .first
            end

            def update(job_id, attributes)
              crawl_job_runs_dataset.where(id: job_id).update(attributes.merge(updated_at: timestamp))
            end

            def hydrate(job)
              job.merge(arguments: JSON.parse(job.fetch(:arguments_json)))
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end

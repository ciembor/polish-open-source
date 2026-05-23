# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          class SQLitePackageCrawlRunRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def create(period, ecosystem:, refresh:)
              validate_ecosystem!(ecosystem)
              period_start = period_start(period)

              database.transaction do
                existing_run = active_run(period_start, ecosystem)
                existing_run ? existing_run.fetch(:id) : insert_run(period_start, ecosystem, refresh)
              end
            end

            def finish(run_id)
              update(run_id, status: 'finished', finished_at: timestamp, error: nil)
            end

            def fail(run_id, error)
              update(run_id, status: 'failed', finished_at: timestamp, error: error)
            end

            private

            attr_reader :clock, :database

            def validate_ecosystem!(ecosystem)
              return if Contexts::Packages::Domain::Ecosystem.supported?(ecosystem)

              raise ArgumentError, "Unsupported package ecosystem: #{ecosystem}"
            end

            def insert_run(period_start, ecosystem, refresh)
              package_crawl_runs.insert(
                period_start: period_start,
                ecosystem: ecosystem,
                status: 'running',
                refresh: refresh ? 1 : 0,
                started_at: timestamp,
                updated_at: timestamp
              )
            end

            def active_run(period_start, ecosystem)
              package_crawl_runs
                .where(period_start: period_start, ecosystem: ecosystem, status: 'running')
                .order(Sequel.desc(:id))
                .first
            end

            def update(run_id, attributes)
              package_crawl_runs.where(id: run_id).update(attributes.merge(updated_at: timestamp))
            end

            def package_crawl_runs
              database.dataset(:package_crawl_runs)
            end

            def period_start(period)
              period.respond_to?(:start_date) ? period.start_date.to_s : period.to_s
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

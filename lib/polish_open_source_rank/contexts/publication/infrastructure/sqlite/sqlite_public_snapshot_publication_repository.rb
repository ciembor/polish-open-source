# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          class SQLitePublicSnapshotPublicationRepository
            REQUIRED_STATS_TABLES = %w[
              user_monthly_stats
              repository_monthly_stats
              organization_monthly_stats
              organization_repository_monthly_stats
            ].freeze

            class VerificationFailed < StandardError; end

            def initialize(
              database,
              clock: -> { Time.now.utc },
              badge_materializer: SQLitePublishedBadgeMaterializer.new(database),
              publication_effects: SQLitePublicSnapshotPublicationEffects.new(database)
            )
              @database = database
              @clock = clock
              @badge_materializer = badge_materializer
              @publication_effects = publication_effects
            end

            def stage(period_start)
              upsert_publication(period_start, status: 'staged', staged_at: timestamp, error: nil)
            end

            def verify(period_start)
              failures = verification_failures(period_start)
              raise VerificationFailed, failures.join(', ') if failures.any?

              upsert_publication(period_start, status: 'verified', verified_at: timestamp, error: nil)
            rescue VerificationFailed => e
              upsert_publication(period_start, status: 'staged', error: e.message)
              raise
            end

            def publish(period_start)
              stage(period_start)
              verify(period_start)
              backup_path = publication_effects.checkpoint_and_backup(period_start)
              database.transaction do
                published_at = timestamp
                previous = published_period
                badge_materializer.materialize(period_start, timestamp: published_at)
                publications.where(status: 'published').update(status: 'superseded', updated_at: published_at)
                upsert_publication(
                  period_start,
                  status: 'published',
                  previous_period_start: previous,
                  published_at: published_at,
                  backup_path: backup_path,
                  error: nil
                )
              end
              publication_effects.refresh_public_database_snapshot
              publication_effects.purge_public_cache
            end

            def refresh_public_database_snapshot
              publication_effects.refresh_public_database_snapshot
            end

            def rollback
              current = published_row
              return unless current&.fetch(:previous_period_start)

              previous = current.fetch(:previous_period_start)
              database.transaction do
                mark_rolled_back(current.fetch(:period_start))
                upsert_publication(previous, status: 'published', published_at: timestamp, error: nil)
              end
              publication_effects.refresh_public_database_snapshot
              publication_effects.purge_public_cache
              previous
            end

            private

            attr_reader :badge_materializer, :clock, :database, :publication_effects

            def verification_failures(period_start)
              [
                monthly_finished_failure(period_start),
                required_stats_failure(period_start),
                package_runs_failure(period_start)
              ].compact
            end

            def monthly_finished_failure(period_start)
              return if database.fetch_value(
                "SELECT 1 FROM sync_runs WHERE period_start = ? AND status = 'finished'",
                [period_start]
              ) == 1

              'monthly rankings are not finished'
            end

            def required_stats_failure(period_start)
              missing = REQUIRED_STATS_TABLES.reject { |table| table_has_period?(table, period_start) }
              return if missing.empty?

              "missing public stats: #{missing.join(', ')}"
            end

            def package_runs_failure(period_start)
              latest_status = database.fetch_value(<<~SQL, [period_start])
                SELECT status
                FROM package_crawl_runs
                WHERE period_start = ?
                ORDER BY datetime(started_at) DESC, id DESC
                LIMIT 1
              SQL
              active_scans = database.fetch_value(<<~SQL, [period_start]).to_i
                SELECT COUNT(*)
                FROM package_repository_scans
                WHERE period_start = ?
                  AND status IN ('pending', 'processing', 'failed')
              SQL
              return if latest_status == 'finished' && active_scans.zero?

              'package crawls are not finished'
            end

            def table_has_period?(table, period_start)
              database.fetch_value("SELECT 1 FROM #{table} WHERE period_start = ? LIMIT 1", [period_start]) == 1
            end

            def published_period
              database.fetch_value("SELECT period_start FROM public_snapshot_publications WHERE status = 'published'")
            end

            def published_row
              database.fetch_all(<<~SQL).first
                SELECT period_start, previous_period_start
                FROM public_snapshot_publications
                WHERE status = 'published'
                LIMIT 1
              SQL
            end

            def mark_rolled_back(period_start)
              publications.where(period_start: period_start).update(
                status: 'rolled_back',
                rolled_back_at: timestamp,
                updated_at: timestamp
              )
            end

            def upsert_publication(period_start, attributes)
              row = publication_attributes(period_start, attributes)
              database.write do
                updated = publications
                          .where(period_start: period_start)
                          .update(row.except(:period_start, :created_at))
                next if updated.positive?

                publications.insert(row)
              end
            end

            def publication_attributes(period_start, attributes)
              attributes.merge(
                period_start: period_start,
                created_at: timestamp,
                updated_at: timestamp
              )
            end

            def publications
              database.dataset(:public_snapshot_publications)
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

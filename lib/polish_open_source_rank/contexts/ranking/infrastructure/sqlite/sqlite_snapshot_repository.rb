# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSnapshotRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
              @record_mapper = SQLiteSnapshotRecordMapper.new(clock: clock)
            end

            def upsert_user(attributes)
              upsert(
                users_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                record_mapper.user_record(attributes)
              )
            end

            def record_contributor_snapshot(snapshot)
              upsert_user(record_mapper.contributor_attributes(snapshot))
              record_user_stats(record_mapper.contributor_stats_attributes(snapshot))
            end

            def record_contributor_profile(snapshot)
              upsert_user(record_mapper.contributor_attributes(snapshot))
            end

            def record_user_stats(attributes)
              upsert(
                user_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  user_github_id: attributes.fetch(:user_github_id)
                },
                record_mapper.user_stats_record(attributes)
              )
            end

            def record_repository_snapshot(snapshot)
              upsert_repository(record_mapper.repository_attributes(snapshot))
              record_repository_stats(record_mapper.repository_stats_attributes(snapshot))
            end

            def record_organization_snapshot(snapshot)
              upsert_organization(record_mapper.organization_attributes(snapshot))
              record_organization_stats(record_mapper.organization_stats_attributes(snapshot))
            end

            def record_organization_profile(snapshot)
              upsert_organization(record_mapper.organization_attributes(snapshot))
            end

            def record_organization_repository_snapshot(snapshot)
              upsert_organization_repository(record_mapper.organization_repository_attributes(snapshot))
              record_organization_repository_stats(record_mapper.organization_repository_stats_attributes(snapshot))
            end

            def upsert_repository(attributes)
              upsert(
                repositories_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                record_mapper.repository_record(attributes)
              )
            end

            def record_repository_stats(attributes)
              observed_at = timestamp
              upsert(
                repository_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                record_mapper.repository_stats_record(attributes, observed_at)
              )
              record_repository_star_observation(attributes, observed_at)
            end

            def previous_repository_stars(period, platform, repository_source_id)
              previous_repository_stargazers_count(period, platform, repository_source_id)
            end

            def previous_organization_repository_stars(period, platform, repository_source_id)
              previous_organization_repository_stargazers_count(period, platform, repository_source_id)
            end

            def previous_repository_stargazers_count(period, platform, repository_github_id)
              database.fetch_value(<<~SQL, [platform, repository_github_id, period.start_date.to_s])
                SELECT stargazers_count
                FROM repository_star_observations
                WHERE platform = ?
                  AND repository_github_id = ?
                  AND period_start < ?
                ORDER BY period_start DESC
                LIMIT 1
              SQL
            end

            def previous_organization_repository_stargazers_count(period, platform, repository_github_id)
              database.fetch_value(<<~SQL, [platform, repository_github_id, period.start_date.to_s])
                SELECT stargazers_count
                FROM organization_repository_star_observations
                WHERE platform = ?
                  AND repository_github_id = ?
                  AND period_start < ?
                ORDER BY period_start DESC
                LIMIT 1
              SQL
            end

            private

            attr_reader :clock, :database, :record_mapper

            def users_dataset
              database.dataset(:users)
            end

            def user_stats_dataset
              database.dataset(:user_monthly_stats)
            end

            def organizations_dataset
              database.dataset(:organizations)
            end

            def organization_stats_dataset
              database.dataset(:organization_monthly_stats)
            end

            def repositories_dataset
              database.dataset(:repositories)
            end

            def organization_repositories_dataset
              database.dataset(:organization_repositories)
            end

            def repository_stats_dataset
              database.dataset(:repository_monthly_stats)
            end

            def organization_repository_stats_dataset
              database.dataset(:organization_repository_monthly_stats)
            end

            def repository_star_observations_dataset
              database.dataset(:repository_star_observations)
            end

            def organization_repository_star_observations_dataset
              database.dataset(:organization_repository_star_observations)
            end

            def record_repository_star_observation(attributes, observed_at)
              upsert(
                repository_star_observations_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id),
                  stargazers_count: attributes.fetch(:stargazers_count),
                  observed_at: observed_at
                }
              )
            end

            def upsert_organization(attributes)
              upsert(
                organizations_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                record_mapper.organization_record(attributes)
              )
            end

            def record_organization_stats(attributes)
              upsert(
                organization_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  organization_github_id: attributes.fetch(:organization_github_id)
                },
                record_mapper.organization_stats_record(attributes)
              )
            end

            def upsert_organization_repository(attributes)
              upsert(
                organization_repositories_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                record_mapper.organization_repository_record(attributes)
              )
            end

            def record_organization_repository_stats(attributes)
              observed_at = timestamp
              upsert(
                organization_repository_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                record_mapper.organization_repository_stats_record(attributes, observed_at)
              )
              record_organization_repository_star_observation(attributes, observed_at)
            end

            def record_organization_repository_star_observation(attributes, observed_at)
              upsert(
                organization_repository_star_observations_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id),
                  stargazers_count: attributes.fetch(:stargazers_count),
                  observed_at: observed_at
                }
              )
            end

            def upsert(dataset, identity, attributes)
              scoped = dataset.where(identity)

              database.transaction do
                next unless scoped.update(update_attributes(attributes, identity)).zero?

                dataset.insert(attributes)
              end
            rescue Sequel::UniqueConstraintViolation
              scoped.update(update_attributes(attributes, identity))
            end

            def update_attributes(attributes, identity)
              attributes.except(*identity.keys)
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

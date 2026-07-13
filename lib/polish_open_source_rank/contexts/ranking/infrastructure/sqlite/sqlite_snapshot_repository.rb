# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSnapshotRepository
            REFRESH_ORGANIZATION_REPOSITORY_STAR_DELTAS_SQL = <<~SQL
              UPDATE organization_repository_monthly_stats
              SET monthly_stars_delta = COALESCE((
                    SELECT MAX(
                             organization_repository_monthly_stats.stargazers_count -
                               previous_stats.stargazers_count,
                             0
                           )
                    FROM organization_repository_monthly_stats previous_stats
                    WHERE previous_stats.period_start = ?
                      AND previous_stats.platform = organization_repository_monthly_stats.platform
                      AND previous_stats.repository_github_id =
                          organization_repository_monthly_stats.repository_github_id
                  ), 0),
                  updated_at = ?
              WHERE period_start = ? AND platform = ?
            SQL

            REFRESH_ORGANIZATION_REPOSITORY_METRICS_SQL = <<~SQL
              UPDATE organization_monthly_stats
              SET public_repo_count = COALESCE((
                    SELECT COUNT(*)
                    FROM organization_repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = organization_monthly_stats.period_start
                      AND repository_stats.platform = organization_monthly_stats.platform
                      AND repository_stats.organization_github_id =
                          organization_monthly_stats.organization_github_id
                  ), 0),
                  total_stars = COALESCE((
                    SELECT SUM(repository_stats.stargazers_count)
                    FROM organization_repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = organization_monthly_stats.period_start
                      AND repository_stats.platform = organization_monthly_stats.platform
                      AND repository_stats.organization_github_id =
                          organization_monthly_stats.organization_github_id
                  ), 0),
                  monthly_stars_delta = COALESCE((
                    SELECT SUM(repository_stats.monthly_stars_delta)
                    FROM organization_repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = organization_monthly_stats.period_start
                      AND repository_stats.platform = organization_monthly_stats.platform
                      AND repository_stats.organization_github_id =
                          organization_monthly_stats.organization_github_id
                  ), 0),
                  updated_at = ?
              WHERE period_start = ? AND platform = ?
            SQL

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
              @record_mapper = SQLiteSnapshotRecordMapper.new(clock: clock)
            end

            def upsert_user(attributes)
              identity = { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) }

              upsert_user_record(identity, record_mapper.user_record(attributes))
            end

            def record_contributor_snapshot(snapshot)
              contributor_attributes = record_mapper.contributor_attributes(snapshot)
              contributor_stats_attributes = record_mapper.contributor_stats_attributes(snapshot)

              database.transaction do
                upsert_user_record_without_transaction(
                  { platform: snapshot.platform, github_id: snapshot.source_id },
                  record_mapper.user_record(contributor_attributes)
                )
                upsert_without_transaction(
                  user_stats_dataset,
                  {
                    period_start: snapshot.period.start_date.to_s,
                    platform: snapshot.platform,
                    user_github_id: snapshot.source_id
                  },
                  record_mapper.user_stats_record(contributor_stats_attributes)
                )
              end
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

            def user_stats_for_period(period, platform)
              database.fetch_all(<<~SQL, [period.start_date.to_s, platform])
                SELECT period_start, platform, user_github_id, user_github_id AS source_id, login, city, country, public_repo_count,
                       total_stars, monthly_stars_delta, merged_pull_requests_count
                FROM user_monthly_stats
                WHERE period_start = ? AND platform = ?
                ORDER BY login ASC
              SQL
            end

            def record_repository_snapshot(snapshot)
              repository_attributes = record_mapper.repository_attributes(snapshot)
              repository_stats_attributes = record_mapper.repository_stats_attributes(snapshot)
              observed_at = timestamp

              database.transaction do
                upsert_without_transaction(
                  repositories_dataset,
                  { platform: snapshot.platform, github_id: snapshot.source_id },
                  record_mapper.repository_record(repository_attributes)
                )
                record_repository_stats_without_transaction(repository_stats_attributes, observed_at)
              end
            end

            def record_organization_snapshot(snapshot)
              organization_attributes = record_mapper.organization_attributes(snapshot)
              organization_stats_attributes = record_mapper.organization_stats_attributes(snapshot)

              database.transaction do
                upsert_without_transaction(
                  organizations_dataset,
                  { platform: snapshot.platform, github_id: snapshot.source_id },
                  record_mapper.organization_record(organization_attributes)
                )
                upsert_without_transaction(
                  organization_stats_dataset,
                  {
                    period_start: snapshot.period.start_date.to_s,
                    platform: snapshot.platform,
                    organization_github_id: snapshot.source_id
                  },
                  record_mapper.organization_stats_record(organization_stats_attributes)
                )
              end
            end

            def record_organization_profile(snapshot)
              upsert_organization(record_mapper.organization_attributes(snapshot))
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

            def organization_stats_for_period(period, platform)
              database.fetch_all(<<~SQL, [period.start_date.to_s, platform])
                SELECT period_start, platform, organization_github_id, organization_github_id AS source_id,
                       login, city, country, public_repo_count,
                       total_stars, monthly_stars_delta, merged_pull_requests_count, members_count
                FROM organization_monthly_stats
                WHERE period_start = ? AND platform = ?
                ORDER BY login ASC
              SQL
            end

            def refresh_organization_repository_star_deltas_from_previous_stats(period, platform:)
              database.execute(
                REFRESH_ORGANIZATION_REPOSITORY_STAR_DELTAS_SQL,
                [previous_period_start(period), timestamp, period.start_date.to_s, platform]
              )
            end

            def refresh_organization_repository_metrics(period, platform:)
              database.execute(
                REFRESH_ORGANIZATION_REPOSITORY_METRICS_SQL,
                [timestamp, period.start_date.to_s, platform]
              )
            end

            def record_organization_repository_snapshot(snapshot)
              repository_attributes = record_mapper.organization_repository_attributes(snapshot)
              repository_stats_attributes = record_mapper.organization_repository_stats_attributes(snapshot)
              observed_at = timestamp

              database.transaction do
                upsert_without_transaction(
                  organization_repositories_dataset,
                  { platform: snapshot.platform, github_id: snapshot.source_id },
                  record_mapper.organization_repository_record(repository_attributes)
                )
                record_organization_repository_stats_without_transaction(repository_stats_attributes, observed_at)
              end
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
              database.transaction { record_repository_stats_without_transaction(attributes, observed_at) }
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

            def upsert_organization(attributes)
              upsert(
                organizations_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                record_mapper.organization_record(attributes)
              )
            end

            def upsert_user_record(identity, attributes)
              database.transaction { upsert_user_record_without_transaction(identity, attributes) }
            rescue Sequel::UniqueConstraintViolation
              update_user_record(users_dataset.where(identity), attributes, identity)
            end

            def upsert_user_record_without_transaction(identity, attributes)
              scoped = users_dataset.where(identity)
              return unless update_user_record(scoped, attributes, identity).zero?

              users_dataset.insert(attributes)
            end

            def update_user_record(scoped, attributes, identity)
              existing = scoped.first
              return scoped.update(redacted_user_update_attributes(attributes)) if deleted_user_record?(existing)

              scoped.update(update_attributes(attributes, identity))
            end

            def deleted_user_record?(record)
              record && record.fetch(:profile_deleted, 0).to_i == 1
            end

            def redacted_user_update_attributes(attributes)
              attributes.slice(:login, :html_url, :updated_at)
            end

            def upsert(dataset, identity, attributes)
              database.transaction { upsert_without_transaction(dataset, identity, attributes) }
            rescue Sequel::UniqueConstraintViolation
              dataset.where(identity).update(update_attributes(attributes, identity))
            end

            def upsert_without_transaction(dataset, identity, attributes)
              scoped = dataset.where(identity)
              return unless scoped.update(update_attributes(attributes, identity)).zero?

              dataset.insert(attributes)
            end

            def record_repository_stats_without_transaction(attributes, observed_at)
              upsert_without_transaction(
                repository_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                record_mapper.repository_stats_record(attributes, observed_at)
              )
              upsert_without_transaction(
                repository_star_observations_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                repository_star_observation_record(attributes, observed_at)
              )
            end

            def record_organization_repository_stats_without_transaction(attributes, observed_at)
              upsert_without_transaction(
                organization_repository_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                record_mapper.organization_repository_stats_record(attributes, observed_at)
              )
              upsert_without_transaction(
                organization_repository_star_observations_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  repository_github_id: attributes.fetch(:repository_github_id)
                },
                repository_star_observation_record(attributes, observed_at)
              )
            end

            def repository_star_observation_record(attributes, observed_at)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                repository_github_id: attributes.fetch(:repository_github_id),
                stargazers_count: attributes.fetch(:stargazers_count),
                observed_at: observed_at
              }
            end

            def update_attributes(attributes, identity)
              attributes.except(*identity.keys)
            end

            def timestamp
              clock.call.iso8601
            end

            def previous_period_start(period)
              (period.start_date << 1).to_s
            end
          end
        end
      end
    end
  end
end

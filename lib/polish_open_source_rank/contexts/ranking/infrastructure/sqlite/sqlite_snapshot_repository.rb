# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          # rubocop:disable Metrics/ClassLength
          class SQLiteSnapshotRepository
            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def upsert_user(attributes)
              upsert(
                users_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                user_record(attributes)
              )
            end

            def record_contributor_snapshot(snapshot)
              upsert_user(contributor_attributes(snapshot))
              record_user_stats(contributor_stats_attributes(snapshot))
            end

            def record_user_stats(attributes)
              upsert(
                user_stats_dataset,
                {
                  period_start: attributes.fetch(:period_start),
                  platform: attributes.fetch(:platform, 'github'),
                  user_github_id: attributes.fetch(:user_github_id)
                },
                user_stats_record(attributes)
              )
            end

            def record_repository_snapshot(snapshot)
              upsert_repository(repository_attributes(snapshot))
              record_repository_stats(repository_stats_attributes(snapshot))
            end

            def record_organization_snapshot(snapshot)
              upsert_organization(organization_attributes(snapshot))
              record_organization_stats(organization_stats_attributes(snapshot))
            end

            def record_organization_repository_snapshot(snapshot)
              upsert_organization_repository(organization_repository_attributes(snapshot))
              record_organization_repository_stats(organization_repository_stats_attributes(snapshot))
            end

            def upsert_repository(attributes)
              upsert(
                repositories_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                repository_record(attributes)
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
                repository_stats_record(attributes, observed_at)
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

            attr_reader :clock, :database

            def contributor_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                login: snapshot.login,
                name: snapshot.name,
                location_raw: snapshot.location_raw,
                city: snapshot.city,
                country: snapshot.country,
                email: snapshot.email,
                homepage: snapshot.homepage,
                html_url: snapshot.html_url,
                avatar_url: snapshot.avatar_url
              }
            end

            def contributor_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                user_github_id: snapshot.source_id,
                login: snapshot.login,
                city: snapshot.city,
                country: snapshot.country,
                public_repo_count: snapshot.public_repository_count,
                total_stars: snapshot.total_stars,
                monthly_stars_delta: snapshot.monthly_stars_delta,
                public_activity_count: snapshot.public_activity_count
              }
            end

            def organization_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                login: snapshot.login,
                name: snapshot.name,
                location_raw: snapshot.location_raw,
                city: snapshot.city,
                country: snapshot.country,
                email: snapshot.email,
                homepage: snapshot.homepage,
                html_url: snapshot.html_url,
                avatar_url: snapshot.avatar_url
              }
            end

            def organization_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                organization_github_id: snapshot.source_id,
                login: snapshot.login,
                city: snapshot.city,
                country: snapshot.country,
                public_repo_count: snapshot.public_repository_count,
                total_stars: snapshot.total_stars,
                monthly_stars_delta: snapshot.monthly_stars_delta
              }
            end

            def repository_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                owner_github_id: snapshot.owner_source_id,
                owner_login: snapshot.owner_login,
                name: snapshot.name,
                full_name: snapshot.full_name,
                description: snapshot.description,
                html_url: snapshot.html_url,
                homepage: snapshot.homepage,
                language: snapshot.language,
                fork: snapshot.fork,
                archived: snapshot.archived
              }
            end

            def repository_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                repository_github_id: snapshot.source_id,
                owner_github_id: snapshot.owner_source_id,
                owner_login: snapshot.owner_login,
                owner_city: snapshot.owner_city,
                owner_country: snapshot.owner_country,
                stargazers_count: snapshot.stars,
                monthly_stars_delta: snapshot.monthly_stars_delta
              }
            end

            def organization_repository_attributes(snapshot)
              {
                platform: snapshot.platform,
                github_id: snapshot.source_id,
                organization_github_id: snapshot.organization_source_id,
                organization_login: snapshot.organization_login,
                name: snapshot.name,
                full_name: snapshot.full_name,
                description: snapshot.description,
                html_url: snapshot.html_url,
                homepage: snapshot.homepage,
                language: snapshot.language,
                fork: snapshot.fork,
                archived: snapshot.archived
              }
            end

            def organization_repository_stats_attributes(snapshot)
              {
                period_start: snapshot.period.start_date.to_s,
                platform: snapshot.platform,
                repository_github_id: snapshot.source_id,
                organization_github_id: snapshot.organization_source_id,
                organization_login: snapshot.organization_login,
                organization_city: snapshot.organization_city,
                organization_country: snapshot.organization_country,
                stargazers_count: snapshot.stars,
                monthly_stars_delta: snapshot.monthly_stars_delta
              }
            end

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

            def user_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                login: attributes.fetch(:login),
                name: attributes[:name],
                location_raw: attributes[:location_raw],
                city: attributes[:city],
                country: attributes[:country],
                email: attributes[:email],
                homepage: attributes[:homepage],
                html_url: attributes.fetch(:html_url),
                avatar_url: attributes[:avatar_url],
                updated_at: timestamp
              }
            end

            def user_stats_record(attributes)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                user_github_id: attributes.fetch(:user_github_id),
                login: attributes.fetch(:login),
                city: attributes[:city],
                country: attributes[:country],
                public_repo_count: attributes.fetch(:public_repo_count),
                total_stars: attributes.fetch(:total_stars),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                public_activity_count: attributes.fetch(:public_activity_count),
                updated_at: timestamp
              }
            end

            def organization_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                login: attributes.fetch(:login),
                name: attributes[:name],
                location_raw: attributes[:location_raw],
                city: attributes[:city],
                country: attributes[:country],
                email: attributes[:email],
                homepage: attributes[:homepage],
                html_url: attributes.fetch(:html_url),
                avatar_url: attributes[:avatar_url],
                updated_at: timestamp
              }
            end

            def organization_stats_record(attributes)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                organization_github_id: attributes.fetch(:organization_github_id),
                login: attributes.fetch(:login),
                city: attributes[:city],
                country: attributes[:country],
                public_repo_count: attributes.fetch(:public_repo_count),
                total_stars: attributes.fetch(:total_stars),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                updated_at: timestamp
              }
            end

            def repository_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                owner_github_id: attributes.fetch(:owner_github_id),
                owner_login: attributes.fetch(:owner_login),
                name: attributes.fetch(:name),
                full_name: attributes.fetch(:full_name),
                description: attributes[:description],
                html_url: attributes.fetch(:html_url),
                homepage: attributes[:homepage],
                language: attributes[:language],
                fork: boolean_int(attributes.fetch(:fork)),
                archived: boolean_int(attributes.fetch(:archived)),
                updated_at: timestamp
              }
            end

            def repository_stats_record(attributes, updated_at)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                repository_github_id: attributes.fetch(:repository_github_id),
                owner_github_id: attributes.fetch(:owner_github_id),
                owner_login: attributes.fetch(:owner_login),
                owner_city: attributes[:owner_city],
                owner_country: attributes[:owner_country],
                stargazers_count: attributes.fetch(:stargazers_count),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                updated_at: updated_at
              }
            end

            def organization_repository_record(attributes)
              {
                platform: attributes.fetch(:platform, 'github'),
                github_id: attributes.fetch(:github_id),
                organization_github_id: attributes.fetch(:organization_github_id),
                organization_login: attributes.fetch(:organization_login),
                name: attributes.fetch(:name),
                full_name: attributes.fetch(:full_name),
                description: attributes[:description],
                html_url: attributes.fetch(:html_url),
                homepage: attributes[:homepage],
                language: attributes[:language],
                fork: boolean_int(attributes.fetch(:fork)),
                archived: boolean_int(attributes.fetch(:archived)),
                updated_at: timestamp
              }
            end

            def organization_repository_stats_record(attributes, updated_at)
              {
                period_start: attributes.fetch(:period_start),
                platform: attributes.fetch(:platform, 'github'),
                repository_github_id: attributes.fetch(:repository_github_id),
                organization_github_id: attributes.fetch(:organization_github_id),
                organization_login: attributes.fetch(:organization_login),
                organization_city: attributes[:organization_city],
                organization_country: attributes[:organization_country],
                stargazers_count: attributes.fetch(:stargazers_count),
                monthly_stars_delta: attributes.fetch(:monthly_stars_delta),
                updated_at: updated_at
              }
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
                organization_record(attributes)
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
                organization_stats_record(attributes)
              )
            end

            def upsert_organization_repository(attributes)
              upsert(
                organization_repositories_dataset,
                { platform: attributes.fetch(:platform, 'github'), github_id: attributes.fetch(:github_id) },
                organization_repository_record(attributes)
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
                organization_repository_stats_record(attributes, observed_at)
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

            def boolean_int(value)
              value ? 1 : 0
            end

            def timestamp
              clock.call.iso8601
            end
          end
          # rubocop:enable Metrics/ClassLength
        end
      end
    end
  end
end

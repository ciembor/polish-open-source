# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteSnapshotRepository
            REPOSITORY_STAR_OBSERVATION_SQL = <<~SQL
              INSERT INTO repository_star_observations(
                period_start, platform, repository_github_id, stargazers_count, observed_at
              )
              VALUES (?, ?, ?, ?, ?)
              ON CONFLICT(period_start, platform, repository_github_id) DO UPDATE SET
                stargazers_count = excluded.stargazers_count,
                observed_at = excluded.observed_at
            SQL

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def upsert_user(attributes)
              database.execute(<<~SQL, user_values(attributes))
                INSERT INTO users(platform, github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(platform, github_id) DO UPDATE SET
                  login = excluded.login,
                  name = excluded.name,
                  location_raw = excluded.location_raw,
                  city = excluded.city,
                  country = excluded.country,
                  email = excluded.email,
                  homepage = excluded.homepage,
                  html_url = excluded.html_url,
                  avatar_url = excluded.avatar_url,
                  updated_at = excluded.updated_at
              SQL
            end

            def record_contributor_snapshot(snapshot)
              upsert_user(contributor_attributes(snapshot))
              record_user_stats(contributor_stats_attributes(snapshot))
            end

            def record_user_stats(attributes)
              database.execute(<<~SQL, user_stats_values(attributes))
                INSERT INTO user_monthly_stats(
                  period_start, platform, user_github_id, login, city, country, public_repo_count,
                  total_stars, monthly_stars_delta, public_activity_count, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(period_start, platform, user_github_id) DO UPDATE SET
                  login = excluded.login,
                  city = excluded.city,
                  country = excluded.country,
                  public_repo_count = excluded.public_repo_count,
                  total_stars = excluded.total_stars,
                  monthly_stars_delta = excluded.monthly_stars_delta,
                  public_activity_count = excluded.public_activity_count,
                  updated_at = excluded.updated_at
              SQL
            end

            def record_repository_snapshot(snapshot)
              upsert_repository(repository_attributes(snapshot))
              record_repository_stats(repository_stats_attributes(snapshot))
            end

            def upsert_repository(attributes)
              database.execute(<<~SQL, repository_values(attributes))
                INSERT INTO repositories(
                  platform, github_id, owner_github_id, owner_login, name, full_name, description,
                  html_url, homepage, language, fork, archived, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(platform, github_id) DO UPDATE SET
                  owner_github_id = excluded.owner_github_id,
                  owner_login = excluded.owner_login,
                  name = excluded.name,
                  full_name = excluded.full_name,
                  description = excluded.description,
                  html_url = excluded.html_url,
                  homepage = excluded.homepage,
                  language = excluded.language,
                  fork = excluded.fork,
                  archived = excluded.archived,
                  updated_at = excluded.updated_at
              SQL
            end

            def record_repository_stats(attributes)
              observed_at = timestamp
              database.execute(<<~SQL, repository_stats_values(attributes, observed_at))
                INSERT INTO repository_monthly_stats(
                  period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
                  owner_country, stargazers_count, monthly_stars_delta, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(period_start, platform, repository_github_id) DO UPDATE SET
                  owner_github_id = excluded.owner_github_id,
                  owner_login = excluded.owner_login,
                  owner_city = excluded.owner_city,
                  owner_country = excluded.owner_country,
                  stargazers_count = excluded.stargazers_count,
                  monthly_stars_delta = excluded.monthly_stars_delta,
                  updated_at = excluded.updated_at
              SQL
              record_repository_star_observation(attributes, observed_at)
            end

            def previous_repository_stars(period, platform, repository_source_id)
              previous_repository_stargazers_count(period, platform, repository_source_id)
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

            def user_values(attributes)
              [
                attributes.fetch(:platform, 'github'), attributes.fetch(:github_id), attributes.fetch(:login),
                attributes[:name], attributes[:location_raw], attributes[:city], attributes[:country],
                attributes[:email], attributes[:homepage], attributes.fetch(:html_url), attributes[:avatar_url],
                timestamp
              ]
            end

            def user_stats_values(attributes)
              [
                attributes.fetch(:period_start), attributes.fetch(:platform, 'github'),
                attributes.fetch(:user_github_id), attributes.fetch(:login), attributes[:city], attributes[:country],
                attributes.fetch(:public_repo_count), attributes.fetch(:total_stars),
                attributes.fetch(:monthly_stars_delta), attributes.fetch(:public_activity_count), timestamp
              ]
            end

            def repository_values(attributes)
              [
                attributes.fetch(:platform, 'github'), attributes.fetch(:github_id),
                attributes.fetch(:owner_github_id), attributes.fetch(:owner_login), attributes.fetch(:name),
                attributes.fetch(:full_name), attributes[:description], attributes.fetch(:html_url),
                attributes[:homepage], attributes[:language], boolean_int(attributes.fetch(:fork)),
                boolean_int(attributes.fetch(:archived)), timestamp
              ]
            end

            def repository_stats_values(attributes, updated_at)
              [
                attributes.fetch(:period_start), attributes.fetch(:platform, 'github'),
                attributes.fetch(:repository_github_id), attributes.fetch(:owner_github_id),
                attributes.fetch(:owner_login), attributes[:owner_city], attributes[:owner_country],
                attributes.fetch(:stargazers_count), attributes.fetch(:monthly_stars_delta), updated_at
              ]
            end

            def record_repository_star_observation(attributes, observed_at)
              database.execute(
                REPOSITORY_STAR_OBSERVATION_SQL,
                [
                  attributes.fetch(:period_start), attributes.fetch(:platform, 'github'),
                  attributes.fetch(:repository_github_id), attributes.fetch(:stargazers_count), observed_at
                ]
              )
            end

            def boolean_int(value)
              value ? 1 : 0
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

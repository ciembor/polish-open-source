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

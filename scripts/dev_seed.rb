# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../lib/polish_open_source_rank'

module PolishOpenSourceRank
  module Scripts
    # rubocop:disable Metrics/ModuleLength
    module DevSeed
      module_function

      USER_COUNT = 100
      REPOS_PER_USER = 3

      def call(now: Time.now.utc)
        configuration = Configuration.load
        database = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
        Infrastructure::PlatformSchemaMigration.new(database, Infrastructure::SQLiteSchema.sql).bootstrap!

        period = Shared::Domain::Period.previous_calendar_month(now)
        period_start = period.start_date.to_s
        period_end = period.end_date.to_s
        timestamp = now.iso8601

        database.transaction do
          ensure_finished_run(database, period_start, period_end, timestamp)
          ensure_seeded_data(database, period_start, timestamp)
        end

        puts "Seeded #{USER_COUNT} demo users for period #{period_start} into #{configuration.database_path}"
      end

      def ensure_finished_run(database, period_start, period_end, timestamp)
        sync_runs = database.dataset(:sync_runs)
        existing = sync_runs.where(period_start: period_start).first
        return if existing

        sync_runs.insert(
          period_start: period_start,
          period_end: period_end,
          status: 'finished',
          started_at: timestamp,
          finished_at: timestamp,
          error: nil
        )
      end

      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
      def ensure_seeded_data(database, period_start, timestamp)
        return if database.dataset(:users).count >= USER_COUNT

        city_names = Contexts::Ranking::Domain::LocationCatalog::CITIES.map { |city| city.fetch(:name) }
        city_names = %w[Krakow Warsaw Wroclaw Gdansk Poznan] if city_names.empty?

        users = database.dataset(:users)
        user_stats = database.dataset(:user_monthly_stats)
        repositories = database.dataset(:repositories)
        repo_stats = database.dataset(:repository_monthly_stats)

        seeded = 0
        USER_COUNT.times do |index|
          github_id = 10_000 + index
          login = format('demo%03d', index + 1)
          city = city_names[index % city_names.length]
          total_stars = ((USER_COUNT - index) * 25) + ((index % 7) * 3)
          delta = [index % 9, 0].max
          activity = (index % 13) + 1

          users.insert(
            platform: 'github',
            github_id: github_id,
            login: login,
            name: "Demo #{index + 1}",
            location_raw: "#{city}, Poland",
            city: city,
            country: 'Poland',
            email: nil,
            homepage: "https://example.com/#{login}",
            html_url: "https://github.com/#{login}",
            avatar_url: "https://avatars.example/#{login}.png",
            updated_at: timestamp
          )

          user_stats.insert(
            period_start: period_start,
            platform: 'github',
            user_github_id: github_id,
            login: login,
            city: city,
            country: 'Poland',
            public_repo_count: REPOS_PER_USER,
            total_stars: total_stars,
            monthly_stars_delta: delta,
            public_activity_count: activity,
            updated_at: timestamp
          )

          REPOS_PER_USER.times do |repo_index|
            repo_id = (github_id * 100) + repo_index + 1
            name = "repo#{repo_index + 1}"
            full_name = "#{login}/#{name}"
            stars = [total_stars - (repo_index * 7), 1].max

            repositories.insert(
              platform: 'github',
              github_id: repo_id,
              owner_github_id: github_id,
              owner_login: login,
              name: name,
              full_name: full_name,
              description: "Demo repository #{repo_index + 1} for #{login}",
              html_url: "https://github.com/#{full_name}",
              homepage: nil,
              language: %w[Ruby JavaScript Go].fetch((index + repo_index) % 3),
              fork: 0,
              archived: 0,
              updated_at: timestamp
            )

            repo_stats.insert(
              period_start: period_start,
              platform: 'github',
              repository_github_id: repo_id,
              owner_github_id: github_id,
              owner_login: login,
              owner_city: city,
              owner_country: 'Poland',
              stargazers_count: stars,
              monthly_stars_delta: [delta - repo_index, 0].max,
              updated_at: timestamp
            )
          end

          seeded += 1
        end

        seeded
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
    end
    # rubocop:enable Metrics/ModuleLength
  end
end

PolishOpenSourceRank::Scripts::DevSeed.call if $PROGRAM_NAME == __FILE__

# frozen_string_literal: true

require 'securerandom'
require 'time'

require_relative '../lib/polish_open_source_rank'

module PolishOpenSourceRank
  module Scripts
    module DevSeed
      module_function

      def call(now: Time.now.utc)
        Seeder.new(now: now).call
      end

      class Seeder
        USER_COUNT = 100
        REPOS_PER_USER = 3

        def initialize(now:)
          @now = now
          @configuration = Configuration.load
          @database = Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
        end

        def call
          Infrastructure::PlatformSchemaMigration.new(database, Infrastructure::SQLiteSchema.sql).bootstrap!
          database.transaction do
            ensure_finished_run
            ensure_seeded_data
          end
          puts "Seeded #{USER_COUNT} demo users for period #{period_start} into #{configuration.database_path}"
        end

        private

        attr_reader :configuration, :database, :now

        def ensure_finished_run
          sync_runs = database.dataset(:sync_runs)
          return if sync_runs.where(period_start: period_start).first

          sync_runs.insert(
            period_start: period_start,
            period_end: period.end_date.to_s,
            status: 'finished',
            started_at: timestamp,
            finished_at: timestamp,
            error: nil
          )
        end

        def ensure_seeded_data
          return if database.dataset(:users).count >= USER_COUNT

          USER_COUNT.times { |index| seed_user(index) }
        end

        def seed_user(index)
          user = demo_user(index)
          database.dataset(:users).insert(user_record(user))
          database.dataset(:user_monthly_stats).insert(user_stats_record(user))
          seed_repositories(user)
        end

        def seed_repositories(user)
          REPOS_PER_USER.times do |repo_index|
            repository = demo_repository(user, repo_index)
            database.dataset(:repositories).insert(repository_record(repository))
            database.dataset(:repository_monthly_stats).insert(repository_stats_record(repository))
          end
        end

        def demo_user(index)
          login = format('demo%03d', index + 1)
          total_stars = ((USER_COUNT - index) * 25) + ((index % 7) * 3)
          {
            github_id: 10_000 + index,
            login: login,
            name: "Demo #{index + 1}",
            city: city_names[index % city_names.length],
            total_stars: total_stars,
            delta: index % 9,
            activity: (index % 13) + 1
          }
        end

        def demo_repository(user, repo_index)
          name = "repo#{repo_index + 1}"
          {
            id: (user.fetch(:github_id) * 100) + repo_index + 1,
            owner: user,
            name: name,
            full_name: "#{user.fetch(:login)}/#{name}",
            stars: [user.fetch(:total_stars) - (repo_index * 7), 1].max,
            delta: [user.fetch(:delta) - repo_index, 0].max,
            language: %w[Ruby JavaScript Go].fetch((user.fetch(:github_id) + repo_index) % 3)
          }
        end

        def user_record(user)
          {
            platform: 'github',
            github_id: user.fetch(:github_id),
            login: user.fetch(:login),
            name: user.fetch(:name),
            location_raw: "#{user.fetch(:city)}, Poland",
            city: user.fetch(:city),
            country: 'Poland',
            email: nil,
            homepage: "https://example.com/#{user.fetch(:login)}",
            html_url: "https://github.com/#{user.fetch(:login)}",
            avatar_url: "https://avatars.example/#{user.fetch(:login)}.png",
            updated_at: timestamp
          }
        end

        def user_stats_record(user)
          {
            period_start: period_start,
            platform: 'github',
            user_github_id: user.fetch(:github_id),
            login: user.fetch(:login),
            city: user.fetch(:city),
            country: 'Poland',
            public_repo_count: REPOS_PER_USER,
            total_stars: user.fetch(:total_stars),
            monthly_stars_delta: user.fetch(:delta),
            public_activity_count: user.fetch(:activity),
            updated_at: timestamp
          }
        end

        def repository_record(repository)
          owner = repository.fetch(:owner)
          {
            platform: 'github',
            github_id: repository.fetch(:id),
            owner_github_id: owner.fetch(:github_id),
            owner_login: owner.fetch(:login),
            name: repository.fetch(:name),
            full_name: repository.fetch(:full_name),
            description: "Demo repository #{repository.fetch(:name)} for #{owner.fetch(:login)}",
            html_url: "https://github.com/#{repository.fetch(:full_name)}",
            homepage: nil,
            language: repository.fetch(:language),
            fork: 0,
            archived: 0,
            updated_at: timestamp
          }
        end

        def repository_stats_record(repository)
          owner = repository.fetch(:owner)
          {
            period_start: period_start,
            platform: 'github',
            repository_github_id: repository.fetch(:id),
            owner_github_id: owner.fetch(:github_id),
            owner_login: owner.fetch(:login),
            owner_city: owner.fetch(:city),
            owner_country: 'Poland',
            stargazers_count: repository.fetch(:stars),
            monthly_stars_delta: repository.fetch(:delta),
            updated_at: timestamp
          }
        end

        def city_names
          @city_names ||= Contexts::Ranking::Domain::LocationCatalog::CITIES
                          .map { |city| city.fetch(:name) }
                          .then { |names| names.empty? ? %w[Krakow Warsaw Wroclaw Gdansk Poznan] : names }
        end

        def period
          @period ||= Shared::Domain::Period.previous_month(now.to_date)
        end

        def period_start
          period.start_date.to_s
        end

        def timestamp
          now.iso8601
        end
      end
    end
  end
end

PolishOpenSourceRank::Scripts::DevSeed.call if $PROGRAM_NAME == __FILE__

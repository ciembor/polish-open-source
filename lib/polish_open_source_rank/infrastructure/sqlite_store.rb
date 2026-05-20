# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class SQLiteStore
      SCHEMA_VERSION = 1
      REPOSITORY_STAR_OBSERVATION_SQL = <<~SQL
        INSERT INTO repository_star_observations(
          period_start, platform, repository_github_id, stargazers_count, observed_at
        )
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(period_start, platform, repository_github_id) DO UPDATE SET
          stargazers_count = excluded.stargazers_count,
          observed_at = excluded.observed_at
      SQL

      def initialize(path)
        @path = Pathname(path)
      end

      def migrate!
        execute_batch('PRAGMA foreign_keys = ON;')
        migration = PlatformSchemaMigration.new(database, schema_sql)
        migration.needed? ? migration.run : create_schema
        self
      end

      def create_run(period, refresh_platforms: [])
        run_lifecycle.create(period, refresh_platforms: refresh_platforms)
      end

      def finish_run(run_id)
        run_lifecycle.finish(run_id)
      end

      def fail_run(run_id, error)
        run_lifecycle.fail(run_id, error)
      end

      def record_candidate(period, login:, source_query:, platform: 'github', source_id: nil, github_id: nil)
        candidate_queue.record(
          period,
          login: login,
          source_query: source_query,
          platform: platform,
          source_id: source_id,
          github_id: github_id
        )
      end

      def pending_candidates(period, limit: 100, platform: nil)
        candidate_queue.pending(period, limit: limit, platform: platform)
      end

      def mark_candidate(period, platform, login, status = nil, error = nil)
        candidate_queue.mark(period, platform, login, status, error)
      end

      def processed_user?(period, platform, github_id = nil)
        candidate_queue.processed_user?(period, platform, github_id)
      end

      def retryable_candidates?(period, platforms: nil)
        run_lifecycle.retryable_candidates?(period, platforms: platforms)
      end

      def upsert_user(attributes)
        execute(<<~SQL, user_values(attributes))
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
        execute(<<~SQL, user_stats_values(attributes))
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
        execute(<<~SQL, repository_values(attributes))
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
        now = Time.now.utc.iso8601
        execute(<<~SQL, repository_stats_values(attributes, now))
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
        record_repository_star_observation(attributes, now)
      end

      def previous_repository_stargazers_count(period, platform, repository_github_id)
        fetch_value(<<~SQL, [platform, repository_github_id, period.start_date.to_s])
          SELECT stargazers_count
          FROM repository_star_observations
          WHERE platform = ?
            AND repository_github_id = ?
            AND period_start < ?
          ORDER BY period_start DESC
          LIMIT 1
        SQL
      end

      def prune_rankings(period, catalog: Domain::LocationCatalog)
        RankingPruner.new(database, catalog: catalog).prune(period)
      end

      def latest_period
        cache_revision_read_model.latest_period
      end

      def public_cache_revision(period_start)
        cache_revision_read_model.public_cache_revision(period_start)
      end

      def completed_periods
        fetch_all(<<~SQL)
          SELECT period_start
          FROM sync_runs
          WHERE status = 'finished'
          ORDER BY period_start DESC
        SQL
      end

      def edition_years
        edition_read_model.years
      end

      def monthly_editions(year, scope: 'poland')
        edition_read_model.monthly_editions(year, scope: scope)
      end

      def recorded_period?(period_start)
        !fetch_value('SELECT 1 FROM sync_runs WHERE period_start = ?', [period_start]).nil?
      end

      def user_rankings(scope, period_start: latest_period)
        ranking_read_model.user_rankings(scope, period_start: period_start)
      end

      def repository_rankings(scope, period_start: latest_period)
        ranking_read_model.repository_rankings(scope, period_start: period_start)
      end

      def user_profile(platform, login, period_start: latest_period)
        profile_read_model.user_profile(platform, login, period_start: period_start)
      end

      def repository_profile(platform, owner, name, period_start: latest_period)
        profile_read_model.repository_profile(platform, owner, name, period_start: period_start)
      end

      def job_progress(now: Time.now.utc)
        job_progress_read_model.call(now: now)
      end

      def record_api_request(platform:, path:, status:, recorded_at: Time.now.utc)
        source_request_log.record_api_request(platform: platform, path: path, status: status, recorded_at: recorded_at)
      end

      def upsert_discord_connection(platform:, user_github_id:, discord_user_id:, discord_username:)
        discord_connection_repository.upsert(
          platform: platform,
          user_github_id: user_github_id,
          discord_user_id: discord_user_id,
          discord_username: discord_username
        )
      end

      def discord_connection(platform, user_github_id)
        discord_connection_repository.find(platform, user_github_id)
      end

      def record_discord_invite(platform:, user_github_id:, code:, url:)
        discord_invite_repository.record(platform: platform, user_github_id: user_github_id, code: code, url: url)
      end

      def discord_invite(platform, user_github_id)
        discord_invite_repository.find(platform, user_github_id)
      end

      def discord_invite_profile(code)
        discord_invite_repository.profile_for_code(code)
      end

      def discord_access(platform, user_github_id, period_start: latest_period)
        contributor_access_read_model.access(platform, user_github_id, period_start: period_start)
      end

      private

      attr_reader :path

      def database
        @database ||= Shared::Infrastructure::SQLite::Database.open(path)
      end

      def create_schema
        execute_batch(schema_sql)
        execute("PRAGMA user_version = #{SCHEMA_VERSION}")
      end

      def execute(sql, params = [])
        database.execute(sql, params)
      end

      def execute_batch(sql)
        database.execute_batch(sql)
      end

      def fetch_all(sql, params = [])
        execute(sql, params).map { |row| symbolize(row) }
      end

      def fetch_value(sql, params = [])
        database.get_first_value(sql, params)
      end

      def run_lifecycle
        @run_lifecycle ||= SQLiteRunLifecycle.new(database)
      end

      def user_values(attributes)
        [
          attributes.fetch(:platform, 'github'), attributes.fetch(:github_id), attributes.fetch(:login),
          attributes[:name], attributes[:location_raw], attributes[:city], attributes[:country], attributes[:email],
          attributes[:homepage], attributes.fetch(:html_url), attributes[:avatar_url], Time.now.utc.iso8601
        ]
      end

      def user_stats_values(attributes)
        [
          attributes.fetch(:period_start), attributes.fetch(:platform, 'github'), attributes.fetch(:user_github_id),
          attributes.fetch(:login), attributes[:city], attributes[:country], attributes.fetch(:public_repo_count),
          attributes.fetch(:total_stars), attributes.fetch(:monthly_stars_delta),
          attributes.fetch(:public_activity_count), Time.now.utc.iso8601
        ]
      end

      def repository_values(attributes)
        [
          attributes.fetch(:platform, 'github'), attributes.fetch(:github_id), attributes.fetch(:owner_github_id),
          attributes.fetch(:owner_login), attributes.fetch(:name), attributes.fetch(:full_name),
          attributes[:description], attributes.fetch(:html_url), attributes[:homepage], attributes[:language],
          boolean_int(attributes.fetch(:fork)), boolean_int(attributes.fetch(:archived)), Time.now.utc.iso8601
        ]
      end

      def repository_stats_values(attributes, updated_at = Time.now.utc.iso8601)
        [
          attributes.fetch(:period_start), attributes.fetch(:platform, 'github'),
          attributes.fetch(:repository_github_id), attributes.fetch(:owner_github_id),
          attributes.fetch(:owner_login), attributes[:owner_city], attributes[:owner_country],
          attributes.fetch(:stargazers_count), attributes.fetch(:monthly_stars_delta), updated_at
        ]
      end

      def record_repository_star_observation(attributes, observed_at)
        execute(
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

      def symbolize(row)
        row.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = value unless key.is_a?(Integer)
        end
      end

      def schema_sql
        SQLiteSchema.sql
      end

      def cache_revision_read_model
        @cache_revision_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteCacheRevisionReadModel.new(
          database
        )
      end

      def ranking_read_model
        @ranking_read_model ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(database)
      end

      def edition_read_model
        @edition_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteEditionReadModel.new(
          database,
          ranking_read_model: ranking_read_model
        )
      end

      def profile_read_model
        @profile_read_model ||= Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel.new(database)
      end

      def contributor_access_read_model
        @contributor_access_read_model ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
      end

      def discord_connection_repository
        @discord_connection_repository ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database)
      end

      def discord_invite_repository
        @discord_invite_repository ||=
          Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database)
      end

      def job_progress_read_model
        @job_progress_read_model ||=
          Contexts::Operations::Infrastructure::SQLite::SQLiteJobProgressReadModel.new(database)
      end

      def candidate_queue
        @candidate_queue ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue.new(database)
      end

      def source_request_log
        @source_request_log ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog.new(database)
      end
    end
  end
end

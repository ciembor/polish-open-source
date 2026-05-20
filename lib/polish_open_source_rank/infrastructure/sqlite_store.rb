# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class SQLiteStore
      SCHEMA_VERSION = 1

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
        snapshot_repository.upsert_user(attributes)
      end

      def record_user_stats(attributes)
        snapshot_repository.record_user_stats(attributes)
      end

      def upsert_repository(attributes)
        snapshot_repository.upsert_repository(attributes)
      end

      def record_repository_stats(attributes)
        snapshot_repository.record_repository_stats(attributes)
      end

      def previous_repository_stargazers_count(period, platform, repository_github_id)
        snapshot_repository.previous_repository_stargazers_count(period, platform, repository_github_id)
      end

      def prune_rankings(period, catalog: Domain::LocationCatalog)
        Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention.new(database, catalog: catalog).prune(period)
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

      def snapshot_repository
        @snapshot_repository ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository.new(database)
      end

      def source_request_log
        @source_request_log ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog.new(database)
      end
    end
  end
end

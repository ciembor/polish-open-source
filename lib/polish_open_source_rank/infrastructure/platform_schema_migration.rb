# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class PlatformSchemaMigration
      def initialize(database, schema_sql)
        @database = database
        @schema_sql = schema_sql
      end

      def bootstrap!
        needed? ? run : create_current_schema
        ensure_current_columns
      end

      def needed?
        table_exists?('users') && !table_columns('users').include?('platform')
      end

      def run
        with_foreign_keys_disabled do
          database.transaction do
            rename_old_tables
            execute_batch(schema_sql)
            copy_github_rows
            drop_old_tables
          end
        end
      end

      private

      attr_reader :database, :schema_sql

      def create_current_schema
        database.transaction { execute_batch(schema_sql) }
      end

      def with_foreign_keys_disabled
        database.execute('PRAGMA foreign_keys = OFF')
        yield
      ensure
        database.execute('PRAGMA foreign_keys = ON')
      end

      def rename_old_tables
        execute_batch(<<~SQL)
          DROP INDEX IF EXISTS idx_user_stats_period_country_total;
          DROP INDEX IF EXISTS idx_user_stats_period_city_delta;
          DROP INDEX IF EXISTS idx_repo_stats_period_country_total;
          DROP INDEX IF EXISTS idx_repo_stats_period_city_delta;
          ALTER TABLE candidate_users RENAME TO candidate_users_old;
          ALTER TABLE users RENAME TO users_old;
          ALTER TABLE user_monthly_stats RENAME TO user_monthly_stats_old;
          ALTER TABLE repositories RENAME TO repositories_old;
          ALTER TABLE repository_monthly_stats RENAME TO repository_monthly_stats_old;
        SQL
      end

      def copy_github_rows
        copy_candidates
        copy_users
        copy_user_stats
        copy_repositories
        copy_repository_stats
        copy_repository_star_observations
      end

      def copy_candidates
        execute_batch(<<~SQL)
          INSERT INTO candidate_users(
            period_start, platform, github_id, login, source_query, status, error, created_at, updated_at
          )
          SELECT period_start, 'github', github_id, login, source_query, status, error, created_at, updated_at
          FROM candidate_users_old;
        SQL
      end

      def copy_users
        execute_batch(<<~SQL)
          INSERT INTO users(
            platform, github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url,
            updated_at
          )
          SELECT 'github', github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url,
                 updated_at
          FROM users_old;
        SQL
      end

      def copy_user_stats
        execute_batch(<<~SQL)
          INSERT INTO user_monthly_stats(
            period_start, platform, user_github_id, login, city, country, public_repo_count,
            total_stars, monthly_stars_delta, updated_at
          )
          SELECT period_start, 'github', user_github_id, login, city, country, public_repo_count,
                 total_stars, monthly_stars_delta, updated_at
          FROM user_monthly_stats_old;
        SQL
      end

      def copy_repositories
        execute_batch(<<~SQL)
          INSERT INTO repositories(
            platform, github_id, owner_github_id, owner_login, name, full_name, description,
            html_url, homepage, language, fork, archived, updated_at
          )
          SELECT 'github', github_id, owner_github_id, owner_login, name, full_name, description,
                 html_url, homepage, language, fork, archived, updated_at
          FROM repositories_old;
        SQL
      end

      def copy_repository_stats
        execute_batch(<<~SQL)
          INSERT INTO repository_monthly_stats(
            period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
            owner_country, stargazers_count, monthly_stars_delta, updated_at
          )
          SELECT period_start, 'github', repository_github_id, owner_github_id, owner_login, owner_city,
                 owner_country, stargazers_count, monthly_stars_delta, updated_at
          FROM repository_monthly_stats_old;
        SQL
      end

      def copy_repository_star_observations
        execute_batch(<<~SQL)
          INSERT INTO repository_star_observations(
            period_start, platform, repository_github_id, stargazers_count, observed_at
          )
          SELECT period_start, platform, repository_github_id, stargazers_count, updated_at
          FROM repository_monthly_stats;
        SQL
      end

      def drop_old_tables
        execute_batch(<<~SQL)
          DROP TABLE candidate_users_old;
          DROP TABLE users_old;
          DROP TABLE user_monthly_stats_old;
          DROP TABLE repositories_old;
          DROP TABLE repository_monthly_stats_old;
        SQL
      end

      def table_columns(table_name)
        database.table_info(table_name).map { |column| column['name'] }
      end

      def table_exists?(table_name)
        database.dataset(:sqlite_master).where(type: 'table', name: table_name).select(1).first
      end

      def execute_batch(sql)
        database.execute_batch(sql)
      end

      def ensure_current_columns
        if table_columns('user_monthly_stats').include?('public_activity_count')
          rebuild_user_monthly_stats_without_public_activity_count
        end
        add_column_unless_exists('users', 'avatar_hidden INTEGER NOT NULL DEFAULT 0')
        add_column_unless_exists('user_monthly_stats', 'merged_pull_requests_count INTEGER NOT NULL DEFAULT 0')
        add_column_unless_exists('organization_monthly_stats', 'merged_pull_requests_count INTEGER NOT NULL DEFAULT 0')
        add_column_unless_exists('organization_monthly_stats', 'members_count INTEGER NOT NULL DEFAULT 0')
        create_discord_sync_jobs
        create_public_snapshot_publications
        create_published_badges
        seed_current_publication
      end

      def rebuild_user_monthly_stats_without_public_activity_count
        with_foreign_keys_disabled do
          database.transaction { rebuild_user_monthly_stats_table }
        end
      end

      def merged_pull_requests_copy_source
        old_columns = table_columns('user_monthly_stats_old_public_activity')
        old_columns.include?('merged_pull_requests_count') ? 'COALESCE(merged_pull_requests_count, 0)' : '0'
      end

      def rebuild_user_monthly_stats_table
        execute_batch(rename_and_recreate_user_monthly_stats_sql)
        database.execute(copy_user_monthly_stats_sql)
        execute_batch('DROP TABLE user_monthly_stats_old_public_activity;')
      end

      def rename_and_recreate_user_monthly_stats_sql
        <<~SQL
          ALTER TABLE user_monthly_stats RENAME TO user_monthly_stats_old_public_activity;
          CREATE TABLE user_monthly_stats (
            period_start TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT 'github',
            user_github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            city TEXT,
            country TEXT,
            public_repo_count INTEGER NOT NULL,
            total_stars INTEGER NOT NULL,
            monthly_stars_delta INTEGER NOT NULL,
            merged_pull_requests_count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, platform, user_github_id),
            FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
          );
        SQL
      end

      def copy_user_monthly_stats_sql
        <<~SQL
          INSERT INTO user_monthly_stats(
            period_start, platform, user_github_id, login, city, country, public_repo_count,
            total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
          )
          SELECT period_start, platform, user_github_id, login, city, country, public_repo_count,
                 total_stars, monthly_stars_delta, #{merged_pull_requests_copy_source}, updated_at
          FROM user_monthly_stats_old_public_activity
        SQL
      end

      def add_column_unless_exists(table_name, column_definition)
        column_name = column_definition.split.first
        return if table_columns(table_name).include?(column_name)

        database.execute("ALTER TABLE #{table_name} ADD COLUMN #{column_definition}")
      end

      def create_discord_sync_jobs
        execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS discord_sync_jobs (
            platform TEXT NOT NULL,
            user_github_id INTEGER NOT NULL,
            action_kind TEXT NOT NULL,
            discord_user_id TEXT NOT NULL,
            discord_username TEXT,
            access_token TEXT,
            welcome_channel_id TEXT,
            status TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            synced_at TEXT,
            PRIMARY KEY(platform, user_github_id, action_kind),
            FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
          );
        SQL
      end

      def create_public_snapshot_publications
        execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS public_snapshot_publications (
            period_start TEXT PRIMARY KEY,
            status TEXT NOT NULL,
            previous_period_start TEXT,
            staged_at TEXT,
            verified_at TEXT,
            published_at TEXT,
            rolled_back_at TEXT,
            backup_path TEXT,
            error TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        SQL
      end

      def create_published_badges
        execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS published_badges (
            period_start TEXT NOT NULL,
            badge_kind TEXT NOT NULL,
            platform TEXT NOT NULL,
            subject_github_id INTEGER NOT NULL,
            label TEXT NOT NULL,
            status TEXT NOT NULL,
            rank INTEGER,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, badge_kind, platform, subject_github_id)
          );

          CREATE INDEX IF NOT EXISTS idx_published_badges_identity
            ON published_badges(badge_kind, platform, subject_github_id, period_start);
        SQL
      end

      def seed_current_publication
        return if database.fetch_value(published_publication_count_sql).to_i.positive?

        period_starts = database.fetch_all(legacy_public_periods_sql).map { |row| row.fetch(:period_start) }
        return if period_starts.empty?

        now = Time.now.utc.iso8601
        period_starts.each_with_index do |period_start, index|
          status = index.zero? ? 'published' : 'superseded'
          database.execute(seed_publication_sql, [period_start, status, now, now, now, now, now])
        end
      end

      def published_publication_count_sql
        "SELECT COUNT(*) FROM public_snapshot_publications WHERE status = 'published'"
      end

      def seed_publication_sql
        <<~SQL
          INSERT OR IGNORE INTO public_snapshot_publications(
            period_start, status, staged_at, verified_at, published_at, created_at, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?)
        SQL
      end

      def legacy_public_periods_sql
        <<~SQL
          SELECT sync_runs.period_start
          FROM sync_runs
          WHERE sync_runs.status = 'finished'
            AND (
              EXISTS (
                SELECT 1 FROM user_monthly_stats user_stats
                WHERE user_stats.period_start = sync_runs.period_start
              )
              OR EXISTS (
                SELECT 1 FROM repository_monthly_stats repository_stats
                WHERE repository_stats.period_start = sync_runs.period_start
              )
              OR EXISTS (
                SELECT 1 FROM organization_monthly_stats organization_stats
                WHERE organization_stats.period_start = sync_runs.period_start
              )
              OR EXISTS (
                SELECT 1 FROM organization_repository_monthly_stats organization_repository_stats
                WHERE organization_repository_stats.period_start = sync_runs.period_start
              )
            )
          ORDER BY sync_runs.period_start DESC
        SQL
      end
    end
  end
end

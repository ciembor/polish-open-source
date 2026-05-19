# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    # rubocop:disable Metrics/ModuleLength
    module SQLiteSchema
      module_function

      def sql
        <<~SQL
          CREATE TABLE IF NOT EXISTS sync_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            period_start TEXT NOT NULL UNIQUE,
            period_end TEXT NOT NULL,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            finished_at TEXT,
            error TEXT
          );

          CREATE TABLE IF NOT EXISTS candidate_users (
            period_start TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT 'github',
            github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            source_query TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            error TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, platform, login)
          );

          CREATE TABLE IF NOT EXISTS users (
            platform TEXT NOT NULL DEFAULT 'github',
            github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            name TEXT,
            location_raw TEXT,
            city TEXT,
            country TEXT,
            email TEXT,
            homepage TEXT,
            html_url TEXT NOT NULL,
            avatar_url TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(platform, github_id),
            UNIQUE(platform, login)
          );

          CREATE TABLE IF NOT EXISTS user_monthly_stats (
            period_start TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT 'github',
            user_github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            city TEXT,
            country TEXT,
            public_repo_count INTEGER NOT NULL,
            total_stars INTEGER NOT NULL,
            monthly_stars_delta INTEGER NOT NULL,
            public_activity_count INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, platform, user_github_id),
            FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
          );

          CREATE TABLE IF NOT EXISTS repositories (
            platform TEXT NOT NULL DEFAULT 'github',
            github_id INTEGER NOT NULL,
            owner_github_id INTEGER NOT NULL,
            owner_login TEXT NOT NULL,
            name TEXT NOT NULL,
            full_name TEXT NOT NULL,
            description TEXT,
            html_url TEXT NOT NULL,
            homepage TEXT,
            language TEXT,
            fork INTEGER NOT NULL,
            archived INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(platform, github_id),
            UNIQUE(platform, full_name),
            FOREIGN KEY(platform, owner_github_id) REFERENCES users(platform, github_id)
          );

          CREATE TABLE IF NOT EXISTS repository_monthly_stats (
            period_start TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT 'github',
            repository_github_id INTEGER NOT NULL,
            owner_github_id INTEGER NOT NULL,
            owner_login TEXT NOT NULL,
            owner_city TEXT,
            owner_country TEXT,
            stargazers_count INTEGER NOT NULL,
            monthly_stars_delta INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, platform, repository_github_id),
            FOREIGN KEY(platform, repository_github_id) REFERENCES repositories(platform, github_id),
            FOREIGN KEY(platform, owner_github_id) REFERENCES users(platform, github_id)
          );

          CREATE TABLE IF NOT EXISTS repository_star_observations (
            period_start TEXT NOT NULL,
            platform TEXT NOT NULL DEFAULT 'github',
            repository_github_id INTEGER NOT NULL,
            stargazers_count INTEGER NOT NULL,
            observed_at TEXT NOT NULL,
            PRIMARY KEY(period_start, platform, repository_github_id)
          );

          CREATE TABLE IF NOT EXISTS api_request_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            platform TEXT NOT NULL,
            path TEXT NOT NULL,
            status INTEGER NOT NULL,
            recorded_at TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS discord_connections (
            platform TEXT NOT NULL,
            user_github_id INTEGER NOT NULL,
            discord_user_id TEXT NOT NULL,
            discord_username TEXT,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(platform, user_github_id),
            UNIQUE(discord_user_id),
            FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
          );

          CREATE TABLE IF NOT EXISTS discord_invites (
            platform TEXT NOT NULL,
            user_github_id INTEGER NOT NULL,
            code TEXT NOT NULL,
            url TEXT NOT NULL,
            created_at TEXT NOT NULL,
            PRIMARY KEY(platform, user_github_id),
            UNIQUE(code),
            FOREIGN KEY(platform, user_github_id) REFERENCES users(platform, github_id)
          );

          CREATE INDEX IF NOT EXISTS idx_user_stats_period_country_total
            ON user_monthly_stats(period_start, country, total_stars, platform);
          CREATE INDEX IF NOT EXISTS idx_user_stats_period_city_delta
            ON user_monthly_stats(period_start, city, monthly_stars_delta, platform);
          CREATE INDEX IF NOT EXISTS idx_candidate_users_period_platform_status_login
            ON candidate_users(period_start, platform, status, login);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_country_total
            ON repository_monthly_stats(period_start, owner_country, stargazers_count, platform);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_city_delta
            ON repository_monthly_stats(period_start, owner_city, monthly_stars_delta, platform);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_platform_owner
            ON repository_monthly_stats(period_start, platform, owner_github_id);
          CREATE INDEX IF NOT EXISTS idx_repo_star_observations_repo_period
            ON repository_star_observations(platform, repository_github_id, period_start);
          CREATE INDEX IF NOT EXISTS idx_api_request_events_recorded_platform
            ON api_request_events(recorded_at, platform);
          CREATE INDEX IF NOT EXISTS idx_discord_connections_user
            ON discord_connections(platform, user_github_id);

          INSERT OR IGNORE INTO repository_star_observations(
            period_start, platform, repository_github_id, stargazers_count, observed_at
          )
          SELECT period_start, platform, repository_github_id, stargazers_count, updated_at
          FROM repository_monthly_stats;
        SQL
      end
    end
    # rubocop:enable Metrics/ModuleLength
  end
end

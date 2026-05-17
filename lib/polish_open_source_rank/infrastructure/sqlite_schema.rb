# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
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

          CREATE INDEX IF NOT EXISTS idx_user_stats_period_country_total
            ON user_monthly_stats(period_start, country, total_stars, platform);
          CREATE INDEX IF NOT EXISTS idx_user_stats_period_city_delta
            ON user_monthly_stats(period_start, city, monthly_stars_delta, platform);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_country_total
            ON repository_monthly_stats(period_start, owner_country, stargazers_count, platform);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_city_delta
            ON repository_monthly_stats(period_start, owner_city, monthly_stars_delta, platform);
        SQL
      end
    end
  end
end

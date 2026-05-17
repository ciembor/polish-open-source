# frozen_string_literal: true

module PolishGithubRank
  module Infrastructure
    class PlatformSchemaMigration
      def initialize(database, schema_sql)
        @database = database
        @schema_sql = schema_sql
      end

      def needed?
        table_exists?('users') && !table_columns('users').include?('platform')
      end

      def run
        rename_old_tables
        execute_batch(schema_sql)
        copy_github_rows
        drop_old_tables
      end

      private

      attr_reader :database, :schema_sql

      def rename_old_tables
        execute_batch(<<~SQL)
          PRAGMA foreign_keys = OFF;
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
            total_stars, monthly_stars_delta, public_activity_count, updated_at
          )
          SELECT period_start, 'github', user_github_id, login, city, country, public_repo_count,
                 total_stars, monthly_stars_delta, public_activity_count, updated_at
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

      def drop_old_tables
        execute_batch(<<~SQL)
          DROP TABLE candidate_users_old;
          DROP TABLE users_old;
          DROP TABLE user_monthly_stats_old;
          DROP TABLE repositories_old;
          DROP TABLE repository_monthly_stats_old;
          PRAGMA foreign_keys = ON;
        SQL
      end

      def table_columns(table_name)
        database.table_info(table_name).map { |column| column['name'] }
      end

      def table_exists?(table_name)
        database.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [table_name])
      end

      def execute_batch(sql)
        database.execute_batch(sql)
      end
    end
  end
end

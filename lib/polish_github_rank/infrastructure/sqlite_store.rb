# frozen_string_literal: true

require "sqlite3"

module PolishGithubRank
  module Infrastructure
    class SQLiteStore
      SCHEMA_VERSION = 1

      def initialize(path)
        @path = Pathname(path)
      end

      def migrate!
        FileUtils.mkdir_p(path.dirname)
        database.execute_batch("PRAGMA foreign_keys = ON;")
        create_schema
        self
      end

      def create_run(period)
        execute(<<~SQL, [period.start_date.to_s, period.end_date.to_s, Time.now.utc.iso8601])
          INSERT INTO sync_runs(period_start, period_end, status, started_at)
          VALUES (?, ?, 'running', ?)
          ON CONFLICT(period_start) DO UPDATE SET
            period_end = excluded.period_end,
            status = 'running',
            started_at = excluded.started_at,
            finished_at = NULL,
            error = NULL
        SQL
        fetch_value("SELECT id FROM sync_runs WHERE period_start = ?", [period.start_date.to_s])
      end

      def finish_run(run_id)
        execute("UPDATE sync_runs SET status = 'finished', finished_at = ? WHERE id = ?", [Time.now.utc.iso8601, run_id])
      end

      def fail_run(run_id, error)
        execute("UPDATE sync_runs SET status = 'failed', error = ? WHERE id = ?", [error, run_id])
      end

      def record_candidate(period, github_id:, login:, source_query:)
        execute(<<~SQL, [period.start_date.to_s, github_id, login, source_query, Time.now.utc.iso8601])
          INSERT INTO candidate_users(period_start, github_id, login, source_query, status, updated_at)
          VALUES (?, ?, ?, ?, 'pending', ?)
          ON CONFLICT(period_start, login) DO UPDATE SET
            github_id = excluded.github_id,
            source_query = candidate_users.source_query || ', ' || excluded.source_query,
            updated_at = excluded.updated_at
        SQL
      end

      def pending_candidates(period, limit: 100)
        fetch_all(<<~SQL, [period.start_date.to_s, limit])
          SELECT github_id, login
          FROM candidate_users
          WHERE period_start = ? AND status = 'pending'
          ORDER BY login COLLATE NOCASE ASC
          LIMIT ?
        SQL
      end

      def mark_candidate(period, login, status, error = nil)
        execute(<<~SQL, [status, error, Time.now.utc.iso8601, period.start_date.to_s, login])
          UPDATE candidate_users
          SET status = ?, error = ?, updated_at = ?
          WHERE period_start = ? AND login = ?
        SQL
      end

      def processed_user?(period, github_id)
        fetch_value(
          "SELECT 1 FROM user_monthly_stats WHERE period_start = ? AND user_github_id = ?",
          [period.start_date.to_s, github_id]
        )
      end

      def upsert_user(attributes)
        execute(<<~SQL, user_values(attributes))
          INSERT INTO users(github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(github_id) DO UPDATE SET
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
            period_start, user_github_id, login, city, country, public_repo_count,
            total_stars, monthly_stars_delta, public_activity_count, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(period_start, user_github_id) DO UPDATE SET
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
            github_id, owner_github_id, owner_login, name, full_name, description,
            html_url, homepage, language, fork, archived, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(github_id) DO UPDATE SET
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
        execute(<<~SQL, repository_stats_values(attributes))
          INSERT INTO repository_monthly_stats(
            period_start, repository_github_id, owner_github_id, owner_login, owner_city,
            owner_country, stargazers_count, monthly_stars_delta, updated_at
          )
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(period_start, repository_github_id) DO UPDATE SET
            owner_github_id = excluded.owner_github_id,
            owner_login = excluded.owner_login,
            owner_city = excluded.owner_city,
            owner_country = excluded.owner_country,
            stargazers_count = excluded.stargazers_count,
            monthly_stars_delta = excluded.monthly_stars_delta,
            updated_at = excluded.updated_at
        SQL
      end

      def latest_period
        fetch_value("SELECT MAX(period_start) FROM user_monthly_stats")
      end

      def user_rankings(scope, period_start: latest_period)
        {
          top: ranked_users(scope, period_start, "total_stars"),
          trending: ranked_users(scope, period_start, "monthly_stars_delta"),
          active: ranked_users(scope, period_start, "public_activity_count")
        }
      end

      def repository_rankings(scope, period_start: latest_period)
        {
          top: ranked_repositories(scope, period_start, "stargazers_count"),
          trending: ranked_repositories(scope, period_start, "monthly_stars_delta")
        }
      end

      private

      attr_reader :path

      def database
        @database ||= SQLite3::Database.new(path.to_s).tap do |connection|
          connection.results_as_hash = true
        end
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
        database.execute(sql, params).map { |row| symbolize(row) }
      end

      def fetch_value(sql, params = [])
        database.get_first_value(sql, params)
      end

      def ranked_users(scope, period_start, order_column)
        sql_scope, params = user_scope(scope)
        fetch_all(<<~SQL, [period_start, *params])
          SELECT users.login, users.name, users.email, users.homepage, users.html_url, users.avatar_url,
                 stats.city, stats.country, stats.public_repo_count, stats.total_stars,
                 stats.monthly_stars_delta, stats.public_activity_count
          FROM user_monthly_stats stats
          INNER JOIN users ON users.github_id = stats.user_github_id
          WHERE stats.period_start = ? AND #{sql_scope}
          ORDER BY stats.#{order_column} DESC, users.login COLLATE NOCASE ASC
          LIMIT 10
        SQL
      end

      def ranked_repositories(scope, period_start, order_column)
        sql_scope, params = repository_scope(scope)
        fetch_all(<<~SQL, [period_start, *params])
          SELECT repositories.full_name, repositories.name, repositories.description, repositories.html_url,
                 repositories.homepage, repositories.language, stats.owner_login, stats.owner_city,
                 stats.owner_country, stats.stargazers_count, stats.monthly_stars_delta
          FROM repository_monthly_stats stats
          INNER JOIN repositories ON repositories.github_id = stats.repository_github_id
          WHERE stats.period_start = ? AND #{sql_scope}
          ORDER BY stats.#{order_column} DESC, repositories.full_name COLLATE NOCASE ASC
          LIMIT 10
        SQL
      end

      def user_scope(scope)
        return ["stats.country = ?", ["Poland"]] if scope == "poland"

        ["stats.city = ?", [Domain::LocationCatalog.city_name(scope)]]
      end

      def repository_scope(scope)
        return ["stats.owner_country = ?", ["Poland"]] if scope == "poland"

        ["stats.owner_city = ?", [Domain::LocationCatalog.city_name(scope)]]
      end

      def user_values(attributes)
        [
          attributes.fetch(:github_id), attributes.fetch(:login), attributes[:name], attributes[:location_raw],
          attributes[:city], attributes[:country], attributes[:email], attributes[:homepage],
          attributes.fetch(:html_url), attributes[:avatar_url], Time.now.utc.iso8601
        ]
      end

      def user_stats_values(attributes)
        [
          attributes.fetch(:period_start), attributes.fetch(:user_github_id), attributes.fetch(:login),
          attributes[:city], attributes[:country], attributes.fetch(:public_repo_count),
          attributes.fetch(:total_stars), attributes.fetch(:monthly_stars_delta),
          attributes.fetch(:public_activity_count), Time.now.utc.iso8601
        ]
      end

      def repository_values(attributes)
        [
          attributes.fetch(:github_id), attributes.fetch(:owner_github_id), attributes.fetch(:owner_login),
          attributes.fetch(:name), attributes.fetch(:full_name), attributes[:description],
          attributes.fetch(:html_url), attributes[:homepage], attributes[:language],
          boolean_int(attributes.fetch(:fork)), boolean_int(attributes.fetch(:archived)), Time.now.utc.iso8601
        ]
      end

      def repository_stats_values(attributes)
        [
          attributes.fetch(:period_start), attributes.fetch(:repository_github_id), attributes.fetch(:owner_github_id),
          attributes.fetch(:owner_login), attributes[:owner_city], attributes[:owner_country],
          attributes.fetch(:stargazers_count), attributes.fetch(:monthly_stars_delta), Time.now.utc.iso8601
        ]
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
            github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            source_query TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            error TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, login)
          );

          CREATE TABLE IF NOT EXISTS users (
            github_id INTEGER PRIMARY KEY,
            login TEXT NOT NULL UNIQUE,
            name TEXT,
            location_raw TEXT,
            city TEXT,
            country TEXT,
            email TEXT,
            homepage TEXT,
            html_url TEXT NOT NULL,
            avatar_url TEXT,
            updated_at TEXT NOT NULL
          );

          CREATE TABLE IF NOT EXISTS user_monthly_stats (
            period_start TEXT NOT NULL,
            user_github_id INTEGER NOT NULL,
            login TEXT NOT NULL,
            city TEXT,
            country TEXT,
            public_repo_count INTEGER NOT NULL,
            total_stars INTEGER NOT NULL,
            monthly_stars_delta INTEGER NOT NULL,
            public_activity_count INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, user_github_id),
            FOREIGN KEY(user_github_id) REFERENCES users(github_id)
          );

          CREATE TABLE IF NOT EXISTS repositories (
            github_id INTEGER PRIMARY KEY,
            owner_github_id INTEGER NOT NULL,
            owner_login TEXT NOT NULL,
            name TEXT NOT NULL,
            full_name TEXT NOT NULL UNIQUE,
            description TEXT,
            html_url TEXT NOT NULL,
            homepage TEXT,
            language TEXT,
            fork INTEGER NOT NULL,
            archived INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            FOREIGN KEY(owner_github_id) REFERENCES users(github_id)
          );

          CREATE TABLE IF NOT EXISTS repository_monthly_stats (
            period_start TEXT NOT NULL,
            repository_github_id INTEGER NOT NULL,
            owner_github_id INTEGER NOT NULL,
            owner_login TEXT NOT NULL,
            owner_city TEXT,
            owner_country TEXT,
            stargazers_count INTEGER NOT NULL,
            monthly_stars_delta INTEGER NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY(period_start, repository_github_id),
            FOREIGN KEY(repository_github_id) REFERENCES repositories(github_id),
            FOREIGN KEY(owner_github_id) REFERENCES users(github_id)
          );

          CREATE INDEX IF NOT EXISTS idx_user_stats_period_country_total
            ON user_monthly_stats(period_start, country, total_stars);
          CREATE INDEX IF NOT EXISTS idx_user_stats_period_city_delta
            ON user_monthly_stats(period_start, city, monthly_stars_delta);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_country_total
            ON repository_monthly_stats(period_start, owner_country, stargazers_count);
          CREATE INDEX IF NOT EXISTS idx_repo_stats_period_city_delta
            ON repository_monthly_stats(period_start, owner_city, monthly_stars_delta);
        SQL
      end
    end
  end
end


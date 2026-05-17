# frozen_string_literal: true

require 'sqlite3'

module PolishGithubRank
  module Infrastructure
    class SQLiteStore
      SCHEMA_VERSION = 1
      RANKING_LIMIT = 100

      def initialize(path)
        @path = Pathname(path)
      end

      def migrate!
        FileUtils.mkdir_p(path.dirname)
        database.execute_batch('PRAGMA foreign_keys = ON;')
        migration = PlatformSchemaMigration.new(database, schema_sql)
        migration.needed? ? migration.run : create_schema
        self
      end

      def create_run(period)
        return if fetch_value(
          'SELECT 1 FROM sync_runs WHERE period_start = ? AND status = ?',
          [period.start_date.to_s, 'finished']
        )

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
        fetch_value('SELECT id FROM sync_runs WHERE period_start = ?', [period.start_date.to_s])
      end

      def finish_run(run_id)
        execute("UPDATE sync_runs SET status = 'finished', finished_at = ? WHERE id = ?",
                [Time.now.utc.iso8601, run_id])
      end

      def fail_run(run_id, error)
        execute(
          "UPDATE sync_runs SET status = 'failed', error = ? WHERE id = ?",
          [error, run_id]
        )
      end

      def record_candidate(period, login:, source_query:, platform: 'github', source_id: nil, github_id: nil)
        source_id ||= github_id
        execute(<<~SQL, [period.start_date.to_s, platform, source_id, login, source_query, Time.now.utc.iso8601])
          INSERT INTO candidate_users(period_start, platform, github_id, login, source_query, status, updated_at)
          VALUES (?, ?, ?, ?, ?, 'pending', ?)
          ON CONFLICT(period_start, platform, login) DO UPDATE SET
            github_id = excluded.github_id,
            source_query = CASE
              WHEN instr(candidate_users.source_query, excluded.source_query) > 0
              THEN candidate_users.source_query
              ELSE candidate_users.source_query || ', ' || excluded.source_query
            END,
            updated_at = excluded.updated_at
        SQL
      end

      def pending_candidates(period, limit: 100, platform: nil)
        platform_sql = platform ? 'AND platform = ?' : ''
        params = [period.start_date.to_s]
        params << platform if platform
        params << limit
        fetch_all(<<~SQL, params)
          SELECT platform, github_id, github_id AS source_id, login
          FROM candidate_users
          WHERE period_start = ? AND status IN ('pending', 'failed') #{platform_sql}
          ORDER BY platform ASC, login COLLATE NOCASE ASC
          LIMIT ?
        SQL
      end

      def mark_candidate(period, platform, login = nil, status = nil, error = nil)
        unless %w[github gitlab codeberg].include?(platform)
          error = status
          status = login
          login = platform
          platform = 'github'
        end
        execute(<<~SQL, [status, error, Time.now.utc.iso8601, period.start_date.to_s, platform, login])
          UPDATE candidate_users
          SET status = ?, error = ?, updated_at = ?
          WHERE period_start = ? AND platform = ? AND login = ?
        SQL
      end

      def processed_user?(period, platform, github_id = nil)
        unless github_id
          github_id = platform
          platform = 'github'
        end
        fetch_value(
          'SELECT 1 FROM user_monthly_stats WHERE period_start = ? AND platform = ? AND user_github_id = ?',
          [period.start_date.to_s, platform, github_id]
        )
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
        execute(<<~SQL, repository_stats_values(attributes))
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
      end

      def prune_rankings(period, catalog: Domain::LocationCatalog)
        RankingPruner.new(database, catalog: catalog).prune(period)
      end

      def latest_period
        fetch_value("SELECT MAX(period_start) FROM sync_runs WHERE status = 'finished'")
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
        fetch_all(<<~SQL)
          SELECT DISTINCT substr(period_start, 1, 4) AS year
          FROM sync_runs
          WHERE #{edition_period_condition}
          ORDER BY year DESC
        SQL
      end

      def monthly_editions(year, scope: 'poland')
        fetch_all(<<~SQL, [year.to_s]).map do |row|
          SELECT period_start
          FROM sync_runs
          WHERE #{edition_period_condition} AND substr(period_start, 1, 4) = ?
          ORDER BY period_start DESC
        SQL
          period_start = row.fetch(:period_start)
          {
            period_start: period_start,
            repositories: ranked_repositories(scope, period_start, 'stargazers_count', limit: 3),
            users_by_stars: ranked_users(scope, period_start, 'total_stars', limit: 3),
            users_by_activity: ranked_users(scope, period_start, 'public_activity_count', limit: 3)
          }
        end
      end

      def recorded_period?(period_start)
        !fetch_value('SELECT 1 FROM sync_runs WHERE period_start = ?', [period_start]).nil?
      end

      def user_rankings(scope, period_start: latest_period)
        {
          top: ranked_users(scope, period_start, 'total_stars'),
          trending: ranked_users(scope, period_start, 'monthly_stars_delta'),
          active: ranked_users(scope, period_start, 'public_activity_count')
        }
      end

      def repository_rankings(scope, period_start: latest_period)
        {
          top: ranked_repositories(scope, period_start, 'stargazers_count'),
          trending: ranked_repositories(scope, period_start, 'monthly_stars_delta')
        }
      end

      def job_progress(now: Time.now.utc)
        SQLiteJobProgress.new(database).call(now: now)
      end

      private

      attr_reader :path

      def database
        @database ||= SQLite3::Database.new(path.to_s).tap do |connection|
          connection.results_as_hash = true
          connection.busy_timeout = 30_000
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

      def ranked_users(scope, period_start, order_column, limit: RANKING_LIMIT)
        sql_scope, params = user_scope(scope)
        fetch_all(<<~SQL, [period_start, *params])
          SELECT users.platform, users.login, users.name, users.email, users.homepage, users.html_url, users.avatar_url,
                 stats.city, stats.country, stats.public_repo_count, stats.total_stars,
                 stats.monthly_stars_delta, stats.public_activity_count
          FROM user_monthly_stats stats
          INNER JOIN users ON users.platform = stats.platform AND users.github_id = stats.user_github_id
          WHERE stats.period_start = ? AND #{sql_scope} #{trending_filter(order_column, 'stats')}
          ORDER BY stats.#{order_column} DESC, users.platform ASC, users.login COLLATE NOCASE ASC
          LIMIT #{bounded_limit(limit)}
        SQL
      end

      def ranked_repositories(scope, period_start, order_column, limit: RANKING_LIMIT)
        sql_scope, params = repository_scope(scope)
        fetch_all(<<~SQL, [period_start, *params])
          SELECT repositories.platform, repositories.full_name, repositories.name, repositories.description, repositories.html_url,
                 repositories.homepage, repositories.language, stats.owner_login, stats.owner_city,
                 stats.owner_country, stats.stargazers_count, stats.monthly_stars_delta
          FROM repository_monthly_stats stats
          INNER JOIN repositories ON repositories.platform = stats.platform AND repositories.github_id = stats.repository_github_id
          WHERE stats.period_start = ? AND #{sql_scope} #{trending_filter(order_column, 'stats')}
          ORDER BY stats.#{order_column} DESC, repositories.platform ASC, repositories.full_name COLLATE NOCASE ASC
          LIMIT #{bounded_limit(limit)}
        SQL
      end

      def edition_period_condition
        <<~SQL
          (
            EXISTS (
              SELECT 1
              FROM user_monthly_stats user_stats
              WHERE user_stats.period_start = sync_runs.period_start
            )
            OR EXISTS (
              SELECT 1
              FROM repository_monthly_stats repository_stats
              WHERE repository_stats.period_start = sync_runs.period_start
            )
          )
        SQL
      end

      def bounded_limit(limit)
        limit.to_i.clamp(1, RANKING_LIMIT)
      end

      def trending_filter(order_column, table_alias)
        order_column == 'monthly_stars_delta' ? "AND #{table_alias}.monthly_stars_delta > 0" : ''
      end

      def user_scope(scope)
        return ['stats.country = ?', ['Poland']] if scope == 'poland'

        ['stats.city = ?', [Domain::LocationCatalog.city_name(scope)]]
      end

      def repository_scope(scope)
        return ['stats.owner_country = ?', ['Poland']] if scope == 'poland'

        ['stats.owner_city = ?', [Domain::LocationCatalog.city_name(scope)]]
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

      def repository_stats_values(attributes)
        [
          attributes.fetch(:period_start), attributes.fetch(:platform, 'github'),
          attributes.fetch(:repository_github_id), attributes.fetch(:owner_github_id),
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
        SQLiteSchema.sql
      end
    end
  end
end

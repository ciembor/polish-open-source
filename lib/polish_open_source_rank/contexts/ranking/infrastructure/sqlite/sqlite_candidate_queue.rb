# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class SQLiteCandidateQueue
            SUPPORTED_PLATFORMS = %w[github gitlab codeberg].freeze
            PROCESSED_USER_SQL = <<~SQL
              SELECT 1
              FROM user_monthly_stats user_stats
              WHERE user_stats.period_start = ?
                AND user_stats.platform = ?
                AND user_stats.user_github_id = ?
                AND (
                  user_stats.public_repo_count = 0
                  OR EXISTS (
                    SELECT 1
                    FROM repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = user_stats.period_start
                      AND repository_stats.platform = user_stats.platform
                      AND repository_stats.owner_github_id = user_stats.user_github_id
                  )
                )
            SQL
            PROCESSED_ORGANIZATION_SQL = <<~SQL
              SELECT 1
              FROM organization_monthly_stats organization_stats
              WHERE organization_stats.period_start = ?
                AND organization_stats.platform = ?
                AND organization_stats.organization_github_id = ?
                AND (
                  organization_stats.public_repo_count = 0
                  OR EXISTS (
                    SELECT 1
                    FROM organization_repository_monthly_stats repository_stats
                    WHERE repository_stats.period_start = organization_stats.period_start
                      AND repository_stats.platform = organization_stats.platform
                      AND repository_stats.organization_github_id = organization_stats.organization_github_id
                  )
                )
            SQL

            def initialize(database, clock: -> { Time.now.utc })
              @database = database
              @clock = clock
            end

            def record(period, login:, source_query:, platform: 'github', source_id: nil, github_id: nil)
              record_in(
                candidate_users_dataset,
                :candidate_users,
                period,
                login: login,
                source_query: source_query,
                platform: platform,
                source_id: source_id,
                github_id: github_id
              )
            end

            def pending(period, limit: 100, platform: nil)
              pending_candidates(period, platform, dataset: candidate_users_dataset)
                .select(
                  :platform,
                  :github_id,
                  Sequel.as(:github_id, :source_id),
                  :login
                )
                .order(Sequel.lit('platform ASC, login COLLATE NOCASE ASC'))
                .limit(limit)
                .all
            end

            def record_organization(period, login:, source_query:, platform: 'github', source_id: nil, github_id: nil)
              record_in(
                candidate_organizations_dataset,
                :candidate_organizations,
                period,
                login: login,
                source_query: source_query,
                platform: platform,
                source_id: source_id,
                github_id: github_id
              )
            end

            def pending_organizations(period, limit: 100, platform: nil)
              pending_candidates(period, platform, dataset: candidate_organizations_dataset)
                .select(
                  :platform,
                  :github_id,
                  Sequel.as(:github_id, :source_id),
                  :login
                )
                .order(Sequel.lit('platform ASC, login COLLATE NOCASE ASC'))
                .limit(limit)
                .all
            end

            def mark(period, platform, login, status = nil, error = nil)
              platform, login, status, error = normalized_mark_arguments(platform, login, status, error)
              candidate_users_dataset
                .where(period_start: period.start_date.to_s, platform: platform, login: login)
                .update(status: status, error: error, updated_at: timestamp)
            end

            def processed_user?(period, platform, github_id = nil)
              platform, github_id = normalized_user_identity(platform, github_id)
              database.fetch_value(PROCESSED_USER_SQL, [period.start_date.to_s, platform, github_id])
            end

            def mark_organization(period, platform, login, status = nil, error = nil)
              platform, login, status, error = normalized_mark_arguments(platform, login, status, error)
              candidate_organizations_dataset
                .where(period_start: period.start_date.to_s, platform: platform, login: login)
                .update(status: status, error: error, updated_at: timestamp)
            end

            def processed_organization?(period, platform, github_id = nil)
              platform, github_id = normalized_user_identity(platform, github_id)
              database.fetch_value(PROCESSED_ORGANIZATION_SQL, [period.start_date.to_s, platform, github_id])
            end

            private

            attr_reader :clock, :database

            def candidate_users_dataset
              database.dataset(:candidate_users)
            end

            def candidate_organizations_dataset
              database.dataset(:candidate_organizations)
            end

            def pending_candidates(period, platform, dataset:)
              candidates = dataset.where(period_start: period.start_date.to_s, status: 'pending')
              platform ? candidates.where(platform: platform) : candidates
            end

            def record_in(dataset, table, period, login:, source_query:, **identity)
              source_id = identity[:source_id] || identity[:github_id]
              dataset
                .insert_conflict(
                  target: %i[period_start platform login],
                  update: {
                    github_id: Sequel[:excluded][:github_id],
                    source_query: merged_source_query(table),
                    updated_at: pending_updated_at(table)
                  }
                )
                .insert(
                  period_start: period.start_date.to_s,
                  platform: identity.fetch(:platform),
                  github_id: source_id,
                  login: login,
                  source_query: source_query,
                  status: 'pending',
                  updated_at: timestamp
                )
            end

            def merged_source_query(table)
              Sequel.lit(
                <<~SQL
                  CASE
                    WHEN instr(#{table}.source_query, excluded.source_query) > 0
                    THEN #{table}.source_query
                    ELSE #{table}.source_query || ', ' || excluded.source_query
                  END
                SQL
              )
            end

            def pending_updated_at(table)
              Sequel.lit(
                <<~SQL
                  CASE
                    WHEN #{table}.status = 'pending' THEN excluded.updated_at
                    ELSE #{table}.updated_at
                  END
                SQL
              )
            end

            def normalized_mark_arguments(platform, login, status, error)
              return [platform, login, status, error] if SUPPORTED_PLATFORMS.include?(platform)

              ['github', platform, login, status]
            end

            def normalized_user_identity(platform, github_id)
              return [platform, github_id] if github_id

              ['github', platform]
            end

            def timestamp
              clock.call.iso8601
            end
          end
        end
      end
    end
  end
end

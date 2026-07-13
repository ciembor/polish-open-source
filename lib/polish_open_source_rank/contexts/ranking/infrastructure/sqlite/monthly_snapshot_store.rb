# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Infrastructure
        module SQLite
          class MonthlySnapshotStore
            def initialize(run_repository:, candidate_queue:, snapshot_repository:, ranking_retention:)
              @run_repository = run_repository
              @candidate_queue = candidate_queue
              @snapshot_repository = snapshot_repository
              @ranking_retention = ranking_retention
            end

            def create_run(period, refresh_platforms: [])
              run_repository.create(period, refresh_platforms: refresh_platforms)
            end

            def finish_run(run_id)
              run_repository.finish(run_id)
            end

            def fail_run(run_id, error)
              run_repository.fail(run_id, error)
            end

            def retryable_candidates?(period, platforms: nil, candidate_types: nil)
              run_repository.retryable_candidates?(period, platforms: platforms, candidate_types: candidate_types)
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

            def record_organization_candidate(period, login:, source_query:, platform: 'github', source_id: nil,
                                              github_id: nil)
              candidate_queue.record_organization(
                period,
                login: login,
                source_query: source_query,
                platform: platform,
                source_id: source_id,
                github_id: github_id
              )
            end

            def pending_organization_candidates(period, limit: 100, platform: nil)
              candidate_queue.pending_organizations(period, limit: limit, platform: platform)
            end

            def mark_candidate(period, platform, login, status = nil, error = nil)
              candidate_queue.mark(period, platform, login, status, error)
            end

            def processed_user?(period, platform, github_id = nil)
              candidate_queue.processed_user?(period, platform, github_id)
            end

            def mark_organization_candidate(period, platform, login, status = nil, error = nil)
              candidate_queue.mark_organization(period, platform, login, status, error)
            end

            def processed_organization?(period, platform, github_id = nil)
              candidate_queue.processed_organization?(period, platform, github_id)
            end

            def record_contributor_snapshot(snapshot)
              snapshot_repository.record_contributor_snapshot(snapshot)
            end

            def record_contributor_profile(snapshot)
              snapshot_repository.record_contributor_profile(snapshot)
            end

            def record_repository_snapshot(snapshot)
              snapshot_repository.record_repository_snapshot(snapshot)
            end

            def record_user_stats(attributes)
              snapshot_repository.record_user_stats(attributes)
            end

            def record_organization_snapshot(snapshot)
              snapshot_repository.record_organization_snapshot(snapshot)
            end

            def record_organization_profile(snapshot)
              snapshot_repository.record_organization_profile(snapshot)
            end

            def record_organization_stats(attributes)
              snapshot_repository.record_organization_stats(attributes)
            end

            def record_organization_repository_snapshot(snapshot)
              snapshot_repository.record_organization_repository_snapshot(snapshot)
            end

            def user_stats_for_period(period, platform:)
              snapshot_repository.user_stats_for_period(period, platform)
            end

            def organization_stats_for_period(period, platform:)
              snapshot_repository.organization_stats_for_period(period, platform)
            end

            def refresh_organization_repository_star_deltas_from_observations(period, platform:)
              snapshot_repository.refresh_organization_repository_star_deltas_from_observations(
                period,
                platform: platform
              )
            end

            def refresh_organization_repository_metrics(period, platform:)
              snapshot_repository.refresh_organization_repository_metrics(period, platform: platform)
            end

            def prune_rankings(period)
              ranking_retention.prune(period)
            end

            private

            attr_reader :candidate_queue, :ranking_retention, :run_repository, :snapshot_repository
          end
        end
      end
    end
  end
end

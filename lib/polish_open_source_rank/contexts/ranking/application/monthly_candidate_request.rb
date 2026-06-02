# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Application
        # Normalizes a pending candidate row before processing touches source or store APIs.
        class MonthlyCandidateRequest
          attr_reader :period, :source

          def initialize(period, source, candidate, refresh, use_snapshot_star_diff)
            @period = period
            @source = source
            @candidate = Domain::SourceCandidate.new(
              platform: candidate.fetch(:platform),
              source_id: candidate.fetch(:source_id),
              login: candidate.fetch(:login)
            )
            @refresh = refresh
            @use_snapshot_star_diff = use_snapshot_star_diff
          end

          def accepted_profile(profile_writer, profile, location)
            profile_writer.accepted_profile(
              period: period,
              source: source,
              profile: profile,
              location: location,
              use_snapshot_star_diff: use_snapshot_star_diff?
            )
          end

          def login
            candidate.login
          end

          def platform
            candidate.platform
          end

          def source_id
            candidate.source_id
          end

          def use_snapshot_star_diff?
            @use_snapshot_star_diff
          end

          def refresh?
            @refresh
          end

          private

          attr_reader :candidate
        end
      end
    end
  end
end

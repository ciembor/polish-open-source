# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Application
        class ShowRankings
          RankingsPage = Struct.new(
            :user_rankings,
            :repository_rankings,
            :organization_rankings,
            :organization_repository_rankings,
            keyword_init: true
          )

          EMPTY_RANKINGS = { top: [], trending: [], active: [] }.freeze

          def initialize(ranking_read_model:)
            @ranking_read_model = ranking_read_model
          end

          def call(scope:, period_start:)
            unless period_start
              return RankingsPage.new(
                user_rankings: EMPTY_RANKINGS,
                repository_rankings: EMPTY_RANKINGS,
                organization_rankings: { top: [], trending: [], members: [] },
                organization_repository_rankings: { top: [], trending: [] }
              )
            end

            RankingsPage.new(
              user_rankings: ranking_read_model.user_rankings(scope, period_start: period_start),
              repository_rankings: ranking_read_model.repository_rankings(scope, period_start: period_start),
              organization_rankings: ranking_read_model.organization_rankings(scope, period_start: period_start),
              organization_repository_rankings: ranking_read_model.organization_repository_rankings(
                scope,
                period_start: period_start
              )
            )
          end

          private

          attr_reader :ranking_read_model
        end
      end
    end
  end
end

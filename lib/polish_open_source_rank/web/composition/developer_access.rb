# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Provides development-only sign-in candidates without exposing ranking read models to routes.
      class DeveloperAccess
        DEFAULT_LIMIT = 100

        def initialize(ranking_read_model:)
          @ranking_read_model = ranking_read_model
        end

        def github_user_options(period_start:, limit: DEFAULT_LIMIT)
          return [] unless period_start

          ranking_read_model
            .user_rankings('poland', period_start: period_start)
            .fetch(:top)
            .first(limit)
        end

        private

        attr_reader :ranking_read_model
      end
    end
  end
end

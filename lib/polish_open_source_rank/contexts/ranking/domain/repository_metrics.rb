# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        RepositoryMetrics = Struct.new(
          :public_repository_count,
          :total_stars,
          :monthly_stars_delta,
          keyword_init: true
        ) do
          def self.empty
            new(public_repository_count: 0, total_stars: 0, monthly_stars_delta: 0)
          end

          def add(repository, monthly_delta)
            self.public_repository_count += 1
            self.total_stars += repository.fetch(:stars)
            self.monthly_stars_delta += monthly_delta
          end
        end
      end
    end
  end
end

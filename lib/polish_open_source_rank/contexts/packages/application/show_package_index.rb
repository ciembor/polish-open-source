# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class ShowPackageIndex
          def initialize(package_ranking_read_model:)
            @package_ranking_read_model = package_ranking_read_model
          end

          def call(period_start:)
            return [] unless period_start

            package_ranking_read_model.ecosystem_cards(period_start: period_start).select do |card|
              Domain::PackageRankingMetric.slugs(ecosystem: card.fetch(:ecosystem)).any?
            end
          end

          private

          attr_reader :package_ranking_read_model
        end
      end
    end
  end
end

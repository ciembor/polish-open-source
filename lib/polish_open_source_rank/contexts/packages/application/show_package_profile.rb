# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Application
        class ShowPackageProfile
          def initialize(package_ranking_read_model:)
            @package_ranking_read_model = package_ranking_read_model
          end

          def call(ecosystem:, package_name:, period_start:)
            return unless period_start

            package_ranking_read_model.package_profile(
              ecosystem: ecosystem,
              package_name: package_name,
              period_start: period_start
            )
          end

          private

          attr_reader :package_ranking_read_model
        end
      end
    end
  end
end

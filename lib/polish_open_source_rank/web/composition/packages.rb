# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Wires package ranking use cases to package-specific read models.
      class Packages
        def initialize(persistence:)
          @persistence = persistence
        end

        def show_package_index
          @show_package_index ||= Contexts::Packages::Application::ShowPackageIndex.new(
            package_ranking_read_model: package_ranking_read_model
          )
        end

        def show_package_ecosystem_rankings
          @show_package_ecosystem_rankings ||= Contexts::Packages::Application::ShowPackageEcosystemRankings.new(
            package_ranking_read_model: package_ranking_read_model
          )
        end

        def show_package_ranking_detail
          @show_package_ranking_detail ||= Contexts::Packages::Application::ShowPackageRankingDetail.new(
            package_ranking_read_model: package_ranking_read_model
          )
        end

        def package_ranking_read_model
          @package_ranking_read_model ||=
            Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel.new(persistence.public_database)
        end

        private

        attr_reader :persistence
      end
    end
  end
end

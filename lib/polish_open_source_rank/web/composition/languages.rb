# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Wires language ranking use cases to language-specific read models.
      class Languages
        def initialize(persistence:)
          @persistence = persistence
        end

        def show_language_index
          @show_language_index ||= Contexts::Languages::Application::ShowLanguageIndex.new(
            language_ranking_read_model: language_ranking_read_model
          )
        end

        def show_language
          @show_language ||= Contexts::Languages::Application::ShowLanguage.new(
            language_ranking_read_model: language_ranking_read_model
          )
        end

        def show_language_ranking_detail
          @show_language_ranking_detail ||= Contexts::Languages::Application::ShowLanguageRankingDetail.new(
            language_ranking_read_model: language_ranking_read_model
          )
        end

        def show_language_repository_ranking_detail
          @show_language_repository_ranking_detail ||=
            Contexts::Languages::Application::ShowLanguageRepositoryRankingDetail.new(
              language_ranking_read_model: language_ranking_read_model
            )
        end

        def language_ranking_read_model
          @language_ranking_read_model ||=
            Contexts::Languages::Infrastructure::SQLite::SQLiteLanguageRankingReadModel.new(persistence.public_database)
        end

        private

        attr_reader :persistence
      end
    end
  end
end

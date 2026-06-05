# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Keeps publication read-model construction behind one boundary shared by publication use cases.
      class PublicationReadModels
        def initialize(persistence:)
          @persistence = persistence
        end

        def cache_revision
          @cache_revision ||= Contexts::Publication::Infrastructure::SQLite::SQLiteCacheRevisionReadModel.new(
            persistence.public_database
          )
        end

        def ranking
          @ranking ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(
            persistence.database
          )
        end

        def public_ranking
          @public_ranking ||= Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(
            persistence.public_database
          )
        end

        def profile
          @profile ||= Contexts::Publication::Infrastructure::SQLite::SQLiteProfileReadModel.new(
            persistence.public_database
          )
        end

        def public_profile_repository
          @public_profile_repository ||= public_profile_repositories.then do |repositories|
            next repositories.first if repositories.one?

            Contexts::Publication::Infrastructure::SQLite::ReplicatedPublicProfileRepository.new(repositories)
          end
        end

        def edition
          @edition ||= Contexts::Publication::Infrastructure::SQLite::SQLiteEditionReadModel.new(
            persistence.public_database,
            ranking_read_model: public_ranking
          )
        end

        private

        attr_reader :persistence

        def public_profile_repositories
          databases = [persistence.database, persistence.public_writable_database].uniq(&:path)
          databases.map do |database|
            Contexts::Publication::Infrastructure::SQLite::SQLitePublicProfileRepository.new(database)
          end
        end
      end
    end
  end
end

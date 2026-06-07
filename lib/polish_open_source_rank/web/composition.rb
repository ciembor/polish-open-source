# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    # Composition root exposing web-facing use-case clusters without leaking infrastructure wiring to App.
    class Composition
      def initialize(configuration:, github_oauth_client: nil, discord_oauth_client: nil, discord_gateway: nil,
                     discord_role_map: nil)
        @configuration = configuration
        @contexts = {}
        @overrides = {
          github_oauth_client: github_oauth_client,
          discord_oauth_client: discord_oauth_client,
          discord_gateway: discord_gateway,
          discord_role_map: discord_role_map
        }
      end

      def publication
        contexts[:publication] ||= Publication.new(read_models: publication_read_models)
      end

      def packages
        contexts[:packages] ||= Packages.new(package_ranking_read_model: package_ranking_read_model)
      end

      def languages
        contexts[:languages] ||= Languages.new(persistence: persistence)
      end

      def community
        contexts[:community] ||= Community.new(
          configuration: configuration,
          persistence: persistence,
          profile_read_model: publication_read_models.profile,
          overrides: overrides
        )
      end

      def operations
        contexts[:operations] ||= Operations.new(persistence: persistence)
      end

      def public_database
        persistence.public_database
      end

      def sitemap_catalog
        contexts[:sitemap_catalog] ||= SitemapCatalog.new(
          publication_read_models: publication_read_models,
          ranking_catalog: sitemap_ranking_catalog,
          show_rankings: publication.show_rankings,
          list_editions: publication.list_editions
        )
      end

      def development
        contexts[:development] ||= DeveloperAccess.new(ranking_read_model: publication_read_models.ranking)
      end

      private

      attr_reader :configuration, :contexts, :overrides

      def persistence
        contexts[:persistence] ||= Persistence.new(configuration: configuration)
      end

      def publication_read_models
        contexts[:publication_read_models] ||= PublicationReadModels.new(persistence: persistence)
      end

      def package_ranking_read_model
        contexts[:package_ranking_read_model] ||=
          Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel.new(persistence.public_database)
      end

      def sitemap_ranking_catalog
        contexts[:sitemap_ranking_catalog] ||= SitemapRankingCatalog.new(
          catalogs: [
            PublicRankingSitemapCatalog.new(show_ranking_detail: publication.show_ranking_detail),
            LanguageRankingSitemapCatalog.new(
              show_language_ranking_detail: languages.show_language_ranking_detail
            ),
            PackageRankingSitemapCatalog.new(
              package_ranking_read_model: package_ranking_read_model,
              show_package_ranking_detail: packages.show_package_ranking_detail
            )
          ]
        )
      end
    end
  end
end

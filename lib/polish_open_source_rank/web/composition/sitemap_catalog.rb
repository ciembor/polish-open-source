# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class Composition
      # Owns the public URL inventory so sitemap rendering does not reach into read models.
      class SitemapCatalog
        STATIC_PATHS = [
          '/people',
          '/organizations',
          '/about',
          '/editions',
          '/languages',
          '/packages'
        ].freeze

        def initialize(publication_read_models:, ranking_catalog:, show_rankings:, list_editions:)
          @publication_read_models = publication_read_models
          @ranking_catalog = ranking_catalog
          @show_rankings = show_rankings
          @list_editions = list_editions
        end

        def paths(latest_period:)
          STATIC_PATHS + ranking_catalog.paths(
            latest_period: latest_period,
            period_slugs: edition_period_slugs
          ) + edition_paths + profile_paths(latest_period)
        end

        private

        attr_reader :publication_read_models, :ranking_catalog, :show_rankings, :list_editions

        def edition_paths
          edition_years.map { |year| "/editions/#{year}" }
        end

        def profile_paths(latest_period)
          users = identity_paths(publication_read_models.profile.public_user_identities, '/users')
          organizations = identity_paths(
            publication_read_models.profile.public_organization_identities,
            '/organizations'
          )
          return users + organizations unless latest_period

          ranking_page = show_rankings.call(scope: 'poland', period_start: latest_period)
          users + organizations + ranking_repository_paths(ranking_page)
        end

        def ranking_repository_paths(ranking_page)
          repository_paths(ranking_page.repository_rankings, '/repositories') +
            repository_paths(ranking_page.organization_repository_rankings, '/organization-repositories')
        end

        def identity_paths(rows, prefix)
          rows.map { |row| "#{prefix}/#{row.fetch(:platform)}/#{row.fetch(:login)}" }
        end

        def repository_paths(rankings, prefix)
          rankings.values.flatten.map do |row|
            platform = row.fetch(:platform, 'github')
            owner, name = row.fetch(:full_name).split('/', 2)
            "#{prefix}/#{platform}/#{owner}/#{name}"
          end
        end

        def edition_period_slugs
          @edition_period_slugs ||= edition_years.flat_map do |year|
            list_editions.call(year: year).editions.map { |edition| edition.fetch(:period_start)[0, 7] }
          end
        end

        def edition_years
          @edition_years ||= list_editions.call&.years || []
        end
      end
    end
  end
end

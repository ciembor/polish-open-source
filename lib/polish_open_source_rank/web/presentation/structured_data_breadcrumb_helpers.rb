# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataBreadcrumbHelpers
        private

        def breadcrumb_schema
          items = breadcrumb_items
          return if items.length < 2

          {
            '@context' => 'https://schema.org',
            '@type' => 'BreadcrumbList',
            'itemListElement' => items.each_with_index.map do |item, index|
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'name' => item.fetch(:name),
                'item' => full_url(item.fetch(:path))
              }
            end
          }
        end

        def breadcrumb_items
          items = [{ name: 'Polish Open Source', path: localized_public_path('/', locale: current_locale) }]
          items << { name: t('scope.poland'), path: period_base_path('latest') }
          items << { name: scope_name(@scope), path: scope_path(@scope) } if city_scope?
          items.concat(current_page_breadcrumbs)
          items.uniq { |item| item.fetch(:path) }
        end

        def current_page_breadcrumbs
          return package_breadcrumbs if package_page?
          return [{ name: ranking_title(@kind, @metric), path: canonical_path }] if @ranking
          return edition_breadcrumbs if @editions

          current_resource_breadcrumbs || generic_page_breadcrumbs
        end

        def profile_breadcrumbs
          return [{ name: @profile.fetch(:login), path: canonical_path }] if @profile
          return [{ name: @organization.fetch(:login), path: canonical_path }] if @organization
          return [{ name: @repository.fetch(:full_name), path: canonical_path }] if @repository

          [{ name: @organization_repository.fetch(:full_name), path: canonical_path }]
        end

        def current_resource_breadcrumbs
          return profile_breadcrumbs if profile_page? || repository_page?

          [{ name: t('about.title'), path: canonical_path }] if about_page?
        end

        def package_breadcrumbs
          breadcrumbs = [{ name: t('packages.title'), path: package_index_path(period_slug: 'latest') }]
          if @package_ecosystem
            breadcrumbs << { name: @package_ecosystem, path: package_ecosystem_path(@package_ecosystem) }
          end
          breadcrumbs << { name: package_metric_label(@package_metric), path: canonical_path } if @package_ranking
          breadcrumbs
        end

        def generic_page_breadcrumbs
          return [] if canonical_path == localized_public_path('/', locale: current_locale)
          return [] if canonical_path == period_base_path('latest')

          [{ name: @title, path: canonical_path }]
        end

        def edition_breadcrumbs
          breadcrumbs = [{ name: t('editions.title'), path: editions_path }]
          breadcrumbs << { name: @year.to_s, path: canonical_path } if @year
          breadcrumbs
        end
      end
    end
  end
end

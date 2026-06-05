# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module RankingSectionPathHelpers
        def organization_rankings_path(period_slug: @period_slug,
                                       scope_slug: @scope&.fetch(:slug, 'poland') || 'poland')
          if period_slug.nil? || period_slug == 'latest'
            return '/organizations' if scope_slug == 'poland'

            return "/organizations/locations/#{scope_slug}"
          end

          base = "#{period_base_path(period_slug)}/organizations"
          return base if scope_slug == 'poland'

          "#{base}/locations/#{scope_slug}"
        end

        def people_rankings_path(period_slug: @period_slug, scope_slug: @scope&.fetch(:slug, 'poland') || 'poland')
          if period_slug.nil? || period_slug == 'latest'
            return '/people' if scope_slug == 'poland'

            return "/people/locations/#{scope_slug}"
          end

          return period_base_path(period_slug) if scope_slug == 'poland'

          city_path(scope_slug, period_slug: period_slug)
        end

        def latest_ranking_path(kind, metric, scope_slug:)
          if organization_ranking_kind?(kind)
            return latest_organization_ranking_path(kind, metric, scope_slug: scope_slug)
          end

          "#{people_rankings_path(period_slug: 'latest', scope_slug: scope_slug)}/#{kind}/#{metric}"
        end

        def section_scope_path(scope, section: @ranking_section, period_slug: @period_slug)
          scope_slug = scope.fetch(:slug)
          if section == 'organizations'
            return organization_rankings_path(period_slug: period_slug,
                                              scope_slug: scope_slug)
          end

          people_rankings_path(period_slug: period_slug, scope_slug: scope_slug)
        end

        private

        def latest_organization_ranking_path(kind, metric, scope_slug:)
          base = organization_rankings_path(period_slug: 'latest', scope_slug: scope_slug)
          suffix = kind == 'organization-repositories' ? "repositories/#{metric}" : metric

          "#{base}/#{suffix}"
        end

        def organization_ranking_kind?(kind)
          %w[organizations organization-repositories].include?(kind)
        end
      end
    end
  end
end

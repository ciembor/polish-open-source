# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module RankingSectionPathHelpers
        def organization_rankings_path(period_slug: @period_slug,
                                       scope_slug: @scope&.fetch(:slug, 'poland') || 'poland')
          base = "#{period_base_path(period_slug)}/organizations"
          return base if scope_slug == 'poland'

          "#{base}/locations/#{scope_slug}"
        end

        def people_rankings_path(period_slug: @period_slug, scope_slug: @scope&.fetch(:slug, 'poland') || 'poland')
          return period_base_path(period_slug) if scope_slug == 'poland'

          city_path(scope_slug, period_slug: period_slug)
        end

        def section_scope_path(scope, section: @ranking_section, period_slug: @period_slug)
          scope_slug = scope.fetch(:slug)
          if section == 'organizations'
            return organization_rankings_path(period_slug: period_slug,
                                              scope_slug: scope_slug)
          end

          people_rankings_path(period_slug: period_slug, scope_slug: scope_slug)
        end
      end
    end
  end
end

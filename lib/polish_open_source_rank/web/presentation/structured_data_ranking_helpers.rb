# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataRankingHelpers
        private

        def rankings_overview_schema
          sections = ranking_overview_sections
          {
            '@type' => 'ItemList',
            'name' => @title,
            'numberOfItems' => sections.length,
            'itemListElement' => sections.each_with_index.map do |section, index|
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'item' => section
              }
            end
          }
        end

        def ranking_overview_sections
          return organization_ranking_overview_sections if @ranking_section == 'organizations'

          user_ranking_overview_sections + repository_ranking_overview_sections
        end

        def user_ranking_overview_sections
          [
            item_list_schema(
              t('rankings.top_10_stars'),
              @user_rankings.fetch(:top).first(10)
            ) { |row| user_schema(row) },
            item_list_schema(
              t('rankings.trending_10_month'),
              @user_rankings.fetch(:trending).first(10)
            ) { |row| user_schema(row) },
            item_list_schema(
              t('rankings.users_merged_prs_month'),
              @user_rankings.fetch(:active).first(10)
            ) { |row| user_schema(row) }
          ]
        end

        def repository_ranking_overview_sections
          [
            item_list_schema(
              t('rankings.top_10_stars'),
              @repository_rankings.fetch(:top).first(10)
            ) { |row| repository_list_schema(row) },
            item_list_schema(
              t('rankings.trending_10_month'),
              @repository_rankings.fetch(:trending).first(10)
            ) { |row| repository_list_schema(row) }
          ]
        end

        def organization_ranking_overview_sections
          return [] unless @organization_rankings && @organization_repository_rankings

          [
            item_list_schema(
              t('rankings.top_10_stars'),
              @organization_rankings.fetch(:top).first(10)
            ) { |row| organization_list_schema(row) },
            item_list_schema(
              t('rankings.trending_10_month'),
              @organization_rankings.fetch(:trending).first(10)
            ) { |row| organization_list_schema(row) },
            item_list_schema(
              t('rankings.members_10'),
              @organization_rankings.fetch(:members).first(10)
            ) { |row| organization_list_schema(row) },
            item_list_schema(
              t('rankings.organization_repositories_month'),
              @organization_repository_rankings.fetch(:top).first(10)
            ) { |row| organization_repository_list_schema(row) }
          ]
        end

        def ranking_row_schema(row)
          return user_schema(row) if @kind == 'users'
          return organization_list_schema(row) if @kind == 'organizations'
          return organization_repository_list_schema(row) if @kind == 'organization-repositories'

          repository_list_schema(row)
        end
      end
    end
  end
end

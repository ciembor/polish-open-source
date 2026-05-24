# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataCollectionHelpers
        private

        def collection_schema
          return package_dataset_schema if package_collection?
          return ranking_collection_schema if @ranking
          return rankings_overview_schema if @user_rankings || @repository_rankings
          return editions_collection_schema if @editions

          nil
        end

        def package_dataset_schema
          {
            '@type' => 'Dataset',
            'name' => @title,
            'description' => @description,
            'url' => canonical_url,
            'inLanguage' => current_locale,
            'variableMeasured' => package_dataset_metrics,
            'temporalCoverage' => @period
          }.compact
        end

        def package_dataset_metrics
          Contexts::Packages::Domain::PackageRankingMetric.keys.map do |metric|
            { '@type' => 'PropertyValue', 'name' => package_metric_label(metric) }
          end
        end

        def ranking_collection_schema
          {
            '@type' => 'ItemList',
            'name' => ranking_title(@kind, @metric),
            'numberOfItems' => @ranking.length,
            'itemListElement' => item_list_elements(@ranking) { |row| ranking_row_schema(row) }
          }
        end

        def editions_collection_schema
          {
            '@type' => 'ItemList',
            'name' => @title,
            'numberOfItems' => @editions.length,
            'itemListElement' => @editions.each_with_index.map do |edition, index|
              period_slug = Date.parse(edition.fetch(:period_start)).strftime('%Y-%m')
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'url' => full_url(period_base_path(period_slug)),
                'name' => period_label(edition.fetch(:period_start))
              }
            end
          }
        end

        def item_list_schema(name, rows, &)
          {
            '@type' => 'ItemList',
            'name' => name,
            'numberOfItems' => rows.length,
            'itemListElement' => item_list_elements(rows, &)
          }
        end

        def item_list_elements(rows, &)
          rows.each_with_index.map do |row, index|
            {
              '@type' => 'ListItem',
              'position' => index + 1,
              'item' => yield(row)
            }
          end
        end
      end
    end
  end
end

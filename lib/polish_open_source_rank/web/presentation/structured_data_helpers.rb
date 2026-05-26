# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataHelpers
        include StructuredDataBreadcrumbHelpers
        include StructuredDataCollectionHelpers
        include StructuredDataListHelpers
        include StructuredDataPageTypeHelpers
        include StructuredDataProfileHelpers
        include StructuredDataRankingHelpers

        def structured_data
          JSON.pretty_generate(structured_data_payload)
        end

        private

        def structured_data_payload
          nodes = [organization_schema, website_schema, page_schema]
          breadcrumbs = breadcrumb_schema
          nodes << breadcrumbs if breadcrumbs
          nodes.compact
        end

        def website_schema
          return unless localized_page?

          {
            '@context' => 'https://schema.org',
            '@type' => 'WebSite',
            '@id' => full_url('/#website'),
            'name' => 'Polish Open Source',
            'url' => full_url('/'),
            'inLanguage' => current_locale,
            'publisher' => { '@id' => full_url('/#organization') }
          }
        end

        def organization_schema
          return unless localized_page?

          {
            '@context' => 'https://schema.org',
            '@type' => 'Organization',
            '@id' => full_url('/#organization'),
            'name' => 'Polish Open Source',
            'url' => full_url('/'),
            'logo' => full_url(app_path('/icons/polish-open-source.png')),
            'sameAs' => [
              'https://github.com/ciembor/polish-open-source'
            ]
          }
        end

        def page_schema
          base = {
            '@context' => 'https://schema.org',
            '@type' => structured_data_type,
            'name' => @title,
            'description' => @description,
            'url' => canonical_url,
            'inLanguage' => current_locale
          }

          base.merge(page_schema_details)
        end

        def page_schema_details
          return { 'about' => { '@type' => 'Organization', 'name' => 'Polish Open Source Rank' } } if about_page?
          return { 'mainEntity' => collection_schema } if collection_page?
          return { 'mainEntity' => profile_schema } if profile_page?
          return repository_schema if repository_page?

          {}
        end
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataListHelpers
        private

        def user_schema(row)
          {
            '@type' => 'Person',
            'name' => row[:name].to_s.empty? ? row.fetch(:login) : row[:name],
            'alternateName' => row.fetch(:login),
            'url' => full_url(user_profile_path(row)),
            'sameAs' => row.fetch(:html_url)
          }
        end

        def repository_list_schema(row)
          {
            '@type' => 'SoftwareSourceCode',
            'name' => row.fetch(:full_name),
            'url' => full_url(repository_profile_path(row)),
            'codeRepository' => row.fetch(:html_url)
          }.tap do |repository|
            repository['description'] = row[:description] if present_value?(row[:description])
            repository['programmingLanguage'] = row[:language] if present_value?(row[:language])
          end
        end

        def organization_list_schema(row)
          {
            '@type' => 'Organization',
            'name' => row[:name].to_s.empty? ? row.fetch(:login) : row[:name],
            'alternateName' => row.fetch(:login),
            'url' => full_url(organization_profile_path(row)),
            'sameAs' => row.fetch(:html_url)
          }
        end

        def organization_repository_list_schema(row)
          {
            '@type' => 'SoftwareSourceCode',
            'name' => row.fetch(:full_name),
            'url' => full_url(organization_repository_profile_path(row)),
            'codeRepository' => row.fetch(:html_url)
          }.tap do |repository|
            repository['description'] = row[:description] if present_value?(row[:description])
            repository['programmingLanguage'] = row[:language] if present_value?(row[:language])
          end
        end
      end
    end
  end
end

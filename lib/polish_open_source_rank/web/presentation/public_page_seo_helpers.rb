# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module PublicPageSeoHelpers
        private

        def user_profile_seo_title(display_name, source_name)
          t('users.seo.title', user: display_name, platform: source_name)
        end

        def user_profile_seo_description(profile, display_name, source_name)
          key = if present_value?(seo_location(profile))
                  'users.seo.description'
                else
                  'users.seo.description_without_location'
                end
          t(key, user: display_name, platform: source_name, location: seo_location(profile))
        end

        def repository_profile_seo_title(repository, source_name)
          key = if present_value?(repository[:language])
                  'repositories.seo.title'
                else
                  'repositories.seo.title_without_language'
                end
          t(key, repository: repository.fetch(:full_name), platform: source_name, language: repository[:language])
        end

        def repository_profile_seo_description(repository, source_name)
          t(
            'repositories.seo.description',
            repository: repository.fetch(:full_name),
            platform: source_name,
            owner: owner_display_name(repository[:owner_name], repository.fetch(:owner_login)),
            summary: repository_seo_summary(repository)
          )
        end

        def organization_profile_seo_title(display_name, source_name)
          t('organizations.seo.title', organization: display_name, platform: source_name)
        end

        def organization_profile_seo_description(organization, display_name, source_name)
          key = if present_value?(seo_location(organization))
                  'organizations.seo.description'
                else
                  'organizations.seo.description_without_location'
                end
          t(key, organization: display_name, platform: source_name, location: seo_location(organization))
        end

        def organization_repository_profile_seo_title(repository, source_name)
          key = if present_value?(repository[:language])
                  'organization_repositories.seo.title'
                else
                  'organization_repositories.seo.title_without_language'
                end
          t(key, repository: repository.fetch(:full_name), platform: source_name, language: repository[:language])
        end

        def organization_repository_profile_seo_description(repository, source_name)
          t(
            'organization_repositories.seo.description',
            repository: repository.fetch(:full_name),
            platform: source_name,
            owner: owner_display_name(repository[:owner_name], repository.fetch(:organization_login)),
            summary: repository_seo_summary(repository)
          )
        end

        def seo_location(resource)
          resource[:location_raw] || resource[:city] || resource[:country]
        end

        def owner_display_name(name, login)
          return login if name.to_s.empty? || name.to_s.casecmp?(login)

          "#{name} (#{login})"
        end

        def repository_seo_summary(repository)
          parts = []
          if present_value?(repository[:language])
            parts << t('repositories.seo.summary_language', language: repository[:language])
          end
          parts << seo_excerpt(repository[:description]) if present_value?(repository[:description])
          if repository[:stargazers_count]
            parts << t('repositories.seo.summary_stars', stars: repository[:stargazers_count])
          end
          parts.join(' ')
        end

        def seo_excerpt(text, limit: 120)
          normalized = text.to_s.gsub(/\s+/, ' ').strip
          return normalized if normalized.length <= limit

          trimmed = normalized[0, limit].sub(/\s+\S*\z/, '')
          "#{trimmed}..."
        end

        def present_value?(value)
          !value.to_s.strip.empty?
        end
      end
    end
  end
end

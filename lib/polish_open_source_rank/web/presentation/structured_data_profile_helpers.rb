# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      module StructuredDataProfileHelpers
        private

        def profile_schema
          return repository_owner_profile_schema if @repository
          return organization_profile_schema(@organization) if @organization
          return deleted_profile_schema if @profile[:profile_deleted] == 1

          profile = {
            '@type' => 'Person',
            'name' => @profile[:name].to_s.empty? ? @profile.fetch(:login) : @profile[:name],
            'alternateName' => @profile.fetch(:login),
            'url' => canonical_url,
            'sameAs' => @profile.fetch(:html_url)
          }
          add_optional_profile_fields(profile)
          profile
        end

        def deleted_profile_schema
          {
            '@type' => 'Person',
            'name' => @profile.fetch(:login),
            'url' => canonical_url
          }
        end

        def add_optional_profile_fields(profile)
          profile['image'] = @profile[:avatar_url] if present_value?(@profile[:avatar_url])
          location = @profile[:city] || @profile[:country]
          profile['homeLocation'] = location if present_value?(location)
        end

        def repository_schema
          repository = @repository || @organization_repository
          {
            'codeRepository' => repository.fetch(:html_url),
            'programmingLanguage' => repository[:language],
            'author' => repository_owner_profile_schema
          }.compact
        end

        def repository_owner_profile_schema
          return organization_owner_profile_schema if @organization_repository

          {
            '@type' => 'Person',
            'name' => @repository.fetch(:owner_login),
            'url' => full_url(repository_owner_profile_path)
          }
        end

        def organization_owner_profile_schema
          {
            '@type' => 'Organization',
            'name' => @organization_repository.fetch(:organization_login),
            'url' => full_url(
              organization_profile_path(
                platform: @organization_repository.fetch(:platform),
                login: @organization_repository.fetch(:organization_login)
              )
            )
          }
        end

        def organization_profile_schema(organization)
          {
            '@type' => 'Organization',
            'name' => organization[:name].to_s.empty? ? organization.fetch(:login) : organization[:name],
            'alternateName' => organization.fetch(:login),
            'url' => canonical_url,
            'sameAs' => organization.fetch(:html_url)
          }.tap do |profile|
            profile['logo'] = organization[:avatar_url] if present_value?(organization[:avatar_url])
            location = organization[:city] || organization[:country]
            profile['location'] = location if present_value?(location)
          end
        end

        def repository_owner_profile_path
          user_profile_path(platform: @repository.fetch(:platform), login: @repository.fetch(:owner_login))
        end
      end
    end
  end
end

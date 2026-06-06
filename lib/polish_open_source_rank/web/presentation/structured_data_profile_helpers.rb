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

          profile = {
            '@type' => 'Person',
            'name' => @repository[:owner_name].to_s.empty? ? @repository.fetch(:owner_login) : @repository[:owner_name],
            'url' => full_url(repository_owner_profile_path)
          }
          profile['alternateName'] = @repository.fetch(:owner_login) if owner_name_available?(
            @repository[:owner_name],
            @repository.fetch(:owner_login)
          )
          profile
        end

        def organization_owner_profile_schema
          profile = {
            '@type' => 'Organization',
            'name' => organization_owner_name,
            'url' => full_url(
              organization_profile_path(
                platform: @organization_repository.fetch(:platform),
                login: @organization_repository.fetch(:organization_login),
                name: @organization_repository[:owner_name]
              )
            )
          }
          profile['alternateName'] = @organization_repository.fetch(:organization_login) if owner_name_available?(
            @organization_repository[:owner_name],
            @organization_repository.fetch(:organization_login)
          )
          profile
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
          user_profile_path(
            platform: @repository.fetch(:platform),
            login: @repository.fetch(:owner_login),
            name: @repository[:owner_name]
          )
        end

        def organization_owner_name
          name = @organization_repository[:owner_name].to_s
          return @organization_repository.fetch(:organization_login) if name.empty?

          name
        end

        def owner_name_available?(name, login)
          !name.to_s.empty? && name.to_s != login
        end
      end
    end
  end
end

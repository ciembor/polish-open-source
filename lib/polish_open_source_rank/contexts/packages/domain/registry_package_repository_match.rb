# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class RegistryPackageRepositoryMatch
          class Result
            attr_reader :metadata

            def initialize(matched:, rejected:, metadata:)
              @matched = matched
              @rejected = rejected
              @metadata = metadata
            end

            def matched?
              @matched
            end

            def rejected?
              @rejected
            end
          end

          def self.call(package:, manifest:, repository_full_name:)
            new(package: package, manifest: manifest, repository_full_name: repository_full_name).call
          end

          def initialize(package:, manifest:, repository_full_name:)
            @package = package
            @manifest = manifest
            @repository_full_name = repository_full_name.to_s.downcase
          end

          def call
            registry_repositories = github_repositories(registry_urls)
            manifest_repositories = github_repositories(manifest_urls)
            known_repositories = (registry_repositories + manifest_repositories).uniq
            matched = known_repositories.include?(repository_full_name)
            registry_rejected = registry_repositories.any? && !registry_repositories.include?(repository_full_name)

            Result.new(
              matched: matched,
              rejected: registry_rejected,
              metadata: {
                repository_match: matched ? 'matched' : 'unverified',
                registry_repositories: registry_repositories,
                manifest_repositories: manifest_repositories
              }.compact
            )
          end

          private

          attr_reader :manifest, :package, :repository_full_name

          def registry_urls
            [package.repository_url, package.homepage_url]
          end

          def manifest_urls
            [manifest[:repository_url], manifest[:homepage_url], package.package_name]
          end

          def github_repositories(values)
            values.filter_map { |value| github_repository(value) }.uniq
          end

          def github_repository(value)
            text = value.to_s.strip
            match = text.match(%r{github\.com[:/]([^/\s]+)/([^/\s#?]+)}i)
            return unless match

            [match[1], clean_repository_name(match[2])].join('/').downcase
          end

          def clean_repository_name(value)
            value.sub(/\.git\z/i, '')
          end
        end
      end
    end
  end
end

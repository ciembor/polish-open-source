# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          class RepositorySignalRegistryClient
            Registry = Struct.new(:web_url, :metric_source, keyword_init: true)

            REGISTRIES = {
              terraform: Registry.new(
                web_url: 'https://registry.terraform.io/search/modules?q=%s',
                metric_source: 'terraform_registry_popularity_unavailable'
              ),
              conan: Registry.new(
                web_url: 'https://conan.io/center/recipes/%s',
                metric_source: 'conan_center_popularity_unavailable'
              ),
              vcpkg: Registry.new(
                web_url: 'https://vcpkg.io/en/package/%s.html',
                metric_source: 'vcpkg_popularity_unavailable'
              ),
              swiftpm: Registry.new(
                web_url: 'https://swiftpackageindex.com/search?query=%s',
                metric_source: 'swift_package_index_popularity_unavailable'
              ),
              pub: Registry.new(
                web_url: 'https://pub.dev/packages/%s',
                metric_source: 'pub_dev_score_not_mixed_with_rankings'
              ),
              apt: Registry.new(
                web_url: 'https://packages.debian.org/search?keywords=%s',
                metric_source: 'apt_popularity_unavailable'
              ),
              rpm: Registry.new(
                web_url: 'https://src.fedoraproject.org/rpms/%s',
                metric_source: 'rpm_popularity_unavailable'
              ),
              nix: Registry.new(
                web_url: 'https://search.nixos.org/packages?query=%s',
                metric_source: 'nixpkgs_popularity_unavailable'
              )
            }.freeze

            def initialize(ecosystem:, **)
              @ecosystem = ecosystem.to_s
              @registry = REGISTRIES.fetch(ecosystem.to_sym)
            end

            def fetch(package_name)
              package = Domain::RegistryPackage.new(
                ecosystem: ecosystem,
                package_name: package_name,
                registry_url: registry_url(package_name),
                status: 'active'
              )
              snapshot = Domain::RegistryPackageSnapshot.new(
                ecosystem: ecosystem,
                package_name: package_name,
                metadata: { metric_source: registry.metric_source }
              )
              Domain::RegistryFetchResult.new(status: 'ok', package: package, snapshot: snapshot)
            end

            private

            attr_reader :ecosystem, :registry

            def registry_url(package_name)
              registry.web_url.sub('%s', RegistryClientHelpers.escaped_segment(package_name))
            end
          end
        end
      end
    end
  end
end

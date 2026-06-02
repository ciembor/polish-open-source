# frozen_string_literal: true

module PolishOpenSourceRank
  # Owns package registry request-limit environment definitions.
  module PackageRegistryConfigurationDefinitions
    DEFAULTS = {
      npm: 30,
      rubygems: 20,
      crates: 10,
      pypi: 20,
      hex: 20,
      packagist: 20,
      go: 20,
      homebrew: 20,
      nuget: 20,
      maven: 20,
      terraform: 20,
      conan: 20,
      vcpkg: 20,
      swiftpm: 20,
      pub: 20,
      apt: 20,
      rpm: 20,
      nix: 20,
      cran: 20,
      cpan: 20,
      hackage: 20,
      clojars: 20,
      julia: 20,
      conda: 20
    }.freeze

    def self.definitions(constructor:)
      DEFAULTS.to_h do |ecosystem, default|
        [:"#{ecosystem}_registry_requests_per_minute", definition_for(ecosystem, default, constructor)]
      end
    end

    def self.keys
      DEFAULTS.keys
    end

    def self.definition_for(ecosystem, default, constructor)
      {
        env: "#{ecosystem}_registry_requests_per_minute".upcase,
        default: default,
        constructor: constructor
      }
    end
    private_class_method :definition_for
  end
end

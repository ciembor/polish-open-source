# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        class ManifestParserCatalog
          PARSERS = {
            'package.json' => Parsers::NpmPackageJsonParser,
            'Cargo.toml' => Parsers::CargoTomlParser,
            'pyproject.toml' => Parsers::PyProjectTomlParser,
            'setup.cfg' => Parsers::SetupCfgParser,
            'setup.py' => Parsers::SetupPyParser,
            'mix.exs' => Parsers::MixExsParser,
            'gleam.toml' => Parsers::GleamTomlParser,
            'rebar.config' => Parsers::RebarConfigParser,
            'composer.json' => Parsers::ComposerJsonParser,
            'go.mod' => Parsers::GoModParser,
            'Directory.Packages.props' => Parsers::NuGetXmlParser,
            'pom.xml' => Parsers::MavenManifestParser,
            'build.gradle' => Parsers::MavenManifestParser,
            'build.gradle.kts' => Parsers::MavenManifestParser,
            'settings.gradle' => Parsers::MavenManifestParser,
            'settings.gradle.kts' => Parsers::MavenManifestParser,
            'main.tf' => Parsers::TerraformModuleParser,
            'conanfile.py' => Parsers::ConanManifestParser,
            'conanfile.txt' => Parsers::ConanManifestParser,
            'vcpkg.json' => Parsers::VcpkgJsonParser,
            'Package.swift' => Parsers::SwiftPackageParser,
            'pubspec.yaml' => Parsers::PubspecYamlParser,
            'control' => Parsers::DebianControlParser,
            'flake.nix' => Parsers::NixPackageParser,
            'default.nix' => Parsers::NixPackageParser,
            'package.nix' => Parsers::NixPackageParser
          }.freeze

          def parse(path:, ecosystem:, content:)
            parser_for(path, ecosystem).parse(path: path, content: content)
          end

          private

          def parser_for(path, ecosystem)
            return Parsers::RubyGemsGemspecParser.new if ecosystem == 'rubygems'
            return Parsers::HomebrewFormulaParser.new if ecosystem == 'homebrew'
            return Parsers::NuGetXmlParser.new if ecosystem == 'nuget'
            return Parsers::RpmSpecParser.new if ecosystem == 'rpm'

            PARSERS.fetch(File.basename(path)).new
          end
        end
      end
    end
  end
end

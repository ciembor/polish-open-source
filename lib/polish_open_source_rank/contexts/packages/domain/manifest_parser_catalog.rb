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
            'Directory.Packages.props' => Parsers::NuGetXmlParser
          }.freeze

          def parse(path:, ecosystem:, content:)
            parser_for(path, ecosystem).parse(path: path, content: content)
          end

          private

          def parser_for(path, ecosystem)
            return Parsers::RubyGemsGemspecParser.new if ecosystem == 'rubygems'
            return Parsers::HomebrewFormulaParser.new if ecosystem == 'homebrew'
            return Parsers::NuGetXmlParser.new if ecosystem == 'nuget'

            PARSERS.fetch(File.basename(path)).new
          end
        end
      end
    end
  end
end

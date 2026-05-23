# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module Parsers
          class RubyGemsGemspecParser
            Helpers = StaticManifestParserHelpers

            def parse(path:, content:)
              name = Helpers.ruby_assignment(content, 'name')
              PackageManifest.new(
                ecosystem: 'rubygems',
                package_name: name,
                repository_url: Helpers.ruby_metadata(content, 'source_code_uri'),
                homepage_url: Helpers.ruby_assignment(content, 'homepage') ||
                              Helpers.ruby_metadata(content, 'homepage_uri'),
                confidence: name ? 'high' : 'medium',
                parse_status: name ? 'parsed' : 'partial',
                metadata: { path: path, bug_tracker_uri: Helpers.ruby_metadata(content, 'bug_tracker_uri') }.compact
              )
            end
          end
        end
      end
    end
  end
end

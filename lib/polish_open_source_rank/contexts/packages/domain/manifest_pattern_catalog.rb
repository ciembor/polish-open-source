# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Domain
        module ManifestPatternCatalog
          IGNORED_DIRECTORIES = %w[.git build dist node_modules target vendor/bundle].freeze

          FILES = {
            'npm' => ['package.json'],
            'pypi' => %w[pyproject.toml setup.cfg setup.py],
            'crates' => ['Cargo.toml'],
            'hex' => %w[mix.exs gleam.toml rebar.config],
            'packagist' => ['composer.json'],
            'go' => ['go.mod']
          }.freeze

          EXTENSIONS = {
            'rubygems' => ['.gemspec']
          }.freeze

          module_function

          def ignored?(path)
            segments = path.split('/')
            IGNORED_DIRECTORIES.any? { |directory| ignored_directory?(segments, directory) }
          end

          def ecosystem_for(path)
            file_name = path.split('/').last
            FILES.each { |ecosystem, names| return ecosystem if names.include?(file_name) }
            EXTENSIONS.each do |ecosystem, extensions|
              return ecosystem if extensions.any? { |ext| file_name.end_with?(ext) }
            end
            nil
          end

          def ignored_directory?(segments, directory)
            directory_segments = directory.split('/')
            segments.each_cons(directory_segments.length).any? { |candidate| candidate == directory_segments }
          end
        end
      end
    end
  end
end

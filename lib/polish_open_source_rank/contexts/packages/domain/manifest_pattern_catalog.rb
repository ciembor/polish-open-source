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
            'go' => ['go.mod'],
            'nuget' => ['Directory.Packages.props'],
            'maven' => %w[pom.xml build.gradle build.gradle.kts settings.gradle settings.gradle.kts],
            'terraform' => ['main.tf'],
            'conan' => %w[conanfile.py conanfile.txt],
            'vcpkg' => ['vcpkg.json'],
            'swiftpm' => ['Package.swift'],
            'pub' => ['pubspec.yaml'],
            'apt' => ['control'],
            'nix' => %w[flake.nix default.nix package.nix]
          }.freeze

          EXTENSIONS = {
            'rubygems' => ['.gemspec'],
            'nuget' => %w[.csproj .fsproj .vbproj .nuspec],
            'rpm' => ['.spec']
          }.freeze

          module_function

          def ignored?(path)
            segments = path.split('/')
            IGNORED_DIRECTORIES.any? { |directory| ignored_directory?(segments, directory) }
          end

          def ecosystem_for(path)
            special_ecosystem = special_ecosystem_for(path)
            return special_ecosystem if special_ecosystem

            file_name = path.split('/').last
            FILES.each { |ecosystem, names| return ecosystem if names.include?(file_name) }
            EXTENSIONS.each do |ecosystem, extensions|
              return ecosystem if extensions.any? { |ext| file_name.end_with?(ext) }
            end
            nil
          end

          def special_ecosystem_for(path)
            return 'homebrew' if homebrew_formula?(path)
            return 'apt' if debian_control?(path)

            nil
          end

          def homebrew_formula?(path)
            segments = path.split('/')
            segments.include?('Formula') && segments.last.to_s.end_with?('.rb')
          end

          def debian_control?(path)
            path.split('/').last(2) == %w[debian control]
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

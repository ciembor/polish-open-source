# frozen_string_literal: true

module PolishOpenSourceRank
  module Shared
    module Domain
      # Keeps repository owner/name parsing in one place before values cross use-case boundaries.
      class RepositoryFullName
        def self.build(owner:, name:)
          new(owner: owner, name: name)
        end

        def self.parse(value)
          owner, name, extra = value.to_s.split('/')
          raise ArgumentError, "Invalid repository full name: #{value.inspect}" if extra

          build(owner: owner, name: name)
        end

        attr_reader :name

        def initialize(owner:, name:)
          @owner = Login.new(owner)
          @name = repository_name(name)
        end

        def owner
          @owner.to_s
        end

        def to_s
          "#{owner}/#{name}"
        end

        private

        def repository_name(value)
          name = value.to_s
          raise ArgumentError, 'repository name is required' if name.empty?
          raise ArgumentError, "Invalid repository name: #{value.inspect}" if name.include?('/')

          name
        end
      end
    end
  end
end

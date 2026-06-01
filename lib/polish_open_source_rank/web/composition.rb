# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    # Composition root exposing web-facing use-case clusters without leaking infrastructure wiring to App.
    class Composition
      def initialize(configuration:, github_oauth_client: nil, discord_oauth_client: nil, discord_gateway: nil,
                     discord_role_map: nil)
        @configuration = configuration
        @contexts = {}
        @overrides = {
          github_oauth_client: github_oauth_client,
          discord_oauth_client: discord_oauth_client,
          discord_gateway: discord_gateway,
          discord_role_map: discord_role_map
        }
      end

      def publication
        contexts[:publication] ||= Publication.new(persistence: persistence)
      end

      def packages
        contexts[:packages] ||= Packages.new(persistence: persistence)
      end

      def languages
        contexts[:languages] ||= Languages.new(persistence: persistence)
      end

      def community
        contexts[:community] ||= Community.new(
          configuration: configuration,
          persistence: persistence,
          profile_read_model: publication.profile_read_model,
          overrides: overrides
        )
      end

      def operations
        contexts[:operations] ||= Operations.new(persistence: persistence)
      end

      def public_database
        persistence.public_database
      end

      private

      attr_reader :configuration, :contexts, :overrides

      def persistence
        contexts[:persistence] ||= Persistence.new(configuration: configuration)
      end
    end
  end
end

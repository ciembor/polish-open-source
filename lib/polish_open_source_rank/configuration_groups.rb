# frozen_string_literal: true

module PolishOpenSourceRank
  # Value objects used by Configuration to expose related settings without changing legacy getters.
  module ConfigurationGroups
    # HTTP timeout tuple used by source API and user-action network clients.
    class Timeouts
      attr_reader :open_timeout, :read_timeout, :write_timeout

      def initialize(open_timeout:, read_timeout:, write_timeout:)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @write_timeout = write_timeout
      end

      def to_h
        {
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          write_timeout: write_timeout
        }
      end
    end

    # Groups network timeout policies by caller type.
    Network = Data.define(:source_api, :user_action)

    # Groups OAuth client credentials for provider adapters.
    OAuth = Data.define(:github_client_id, :github_client_secret, :discord_client_id, :discord_client_secret)

    # Groups Discord bot and guild settings.
    Discord = Data.define(:bot_token, :guild_id, :invite_channel_id)

    # Groups primary write database and public read database paths.
    Databases = Data.define(:primary, :public)
  end
end

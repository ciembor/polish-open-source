# frozen_string_literal: true

module PolishOpenSourceRank
  # Value objects used by Configuration to expose related settings without changing legacy getters.
  module ConfigurationGroups
    Timeouts = Struct.new(:open_timeout, :read_timeout, :write_timeout, keyword_init: true) do
      def to_h
        {
          open_timeout: open_timeout,
          read_timeout: read_timeout,
          write_timeout: write_timeout
        }
      end
    end

    Network = Struct.new(:source_api, :user_action, keyword_init: true)
    OAuth = Struct.new(:github_client_id, :github_client_secret, :discord_client_id, :discord_client_secret,
                       keyword_init: true)
    Discord = Struct.new(:bot_token, :guild_id, :invite_channel_id, keyword_init: true)
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  # Owns OAuth, Discord, session, and internal auth environment definitions.
  module AuthConfigurationDefinitions
    REQUIRED_KEYS = %i[
      github_oauth_client_id
      github_oauth_client_secret
      discord_oauth_client_id
      discord_oauth_client_secret
      discord_bot_token
      discord_guild_id
      discord_invite_channel_id
    ].freeze

    OPTIONAL_SETTINGS = {
      session_secret: { env: 'SESSION_SECRET' },
      internal_basic_auth_username: { env: 'INTERNAL_BASIC_AUTH_USERNAME' },
      internal_basic_auth_password: { env: 'INTERNAL_BASIC_AUTH_PASSWORD' }
    }.freeze

    def self.definitions
      required_settings.merge(OPTIONAL_SETTINGS)
    end

    def self.required_settings
      REQUIRED_KEYS.to_h do |name|
        [name, { env: name.to_s.upcase, required: true }]
      end
    end
    private_class_method :required_settings
  end
end

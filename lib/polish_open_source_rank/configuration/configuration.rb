# frozen_string_literal: true

require 'dry/configurable'
require_relative 'definitions'
require_relative 'env_file'
require_relative 'groups'
require_relative 'secrets_policy'

module PolishOpenSourceRank
  # Loads application configuration from local env files and process ENV while preserving typed public getters.
  class Configuration
    extend Dry::Configurable

    ConfigurationDefinitions.definitions.each do |name, definition|
      options = {}
      options[:default] = definition[:default] if definition.key?(:default)
      options[:constructor] = definition[:constructor] if definition.key?(:constructor)
      setting name, **options
    end

    def self.load(path = PolishOpenSourceRank.root.join('.env.local'))
      new(path).load
    end

    def initialize(env_path, settings = self.class.config.dup)
      @env_path = env_path
      @settings = settings
    end

    def load
      load_env_file
      apply_env_overrides
      self
    end

    ConfigurationDefinitions.definitions.each do |name, definition|
      next if name == :session_secret

      define_method(name) do
        value = settings.public_send(name)
        return value unless definition[:required] && value.nil?

        ENV.fetch(definition.fetch(:env))
      end
    end

    def session_secret
      secrets.session_secret
    end

    def public_database_path
      database_paths.public
    end

    def internal_basic_auth
      secrets.internal_basic_auth
    end

    def network
      ConfigurationGroups::Network.new(
        source_api: ConfigurationGroups::Timeouts.new(
          open_timeout: http_open_timeout,
          read_timeout: http_read_timeout,
          write_timeout: http_write_timeout
        ),
        user_action: ConfigurationGroups::Timeouts.new(
          open_timeout: user_action_http_open_timeout,
          read_timeout: user_action_http_read_timeout,
          write_timeout: user_action_http_write_timeout
        )
      )
    end

    def oauth
      ConfigurationGroups::OAuth.new(
        github_client_id: github_oauth_client_id,
        github_client_secret: github_oauth_client_secret,
        discord_client_id: discord_oauth_client_id,
        discord_client_secret: discord_oauth_client_secret
      )
    end

    def discord
      ConfigurationGroups::Discord.new(
        bot_token: discord_bot_token,
        guild_id: discord_guild_id,
        invite_channel_id: discord_invite_channel_id
      )
    end

    def database_paths
      public_path = settings.public_database_path.to_s
      ConfigurationGroups::Databases.new(
        primary: database_path,
        public: public_path.empty? ? database_path : public_path
      )
    end

    {
      http_timeouts: :source_api,
      user_action_http_timeouts: :user_action
    }.each do |method_name, network_group|
      define_method(method_name) do
        network.public_send(network_group).to_h
      end
    end

    def package_registry_request_limits
      PackageRegistryConfigurationDefinitions.keys.to_h do |key|
        [key, public_send(:"#{key}_registry_requests_per_minute")]
      end
    end

    def sentry_enabled?
      settings.rack_env != 'test' && !sentry_dsn.to_s.empty?
    end

    def sentry_runtime_environment
      value = sentry_environment.to_s
      value.empty? ? rack_env : value
    end

    private

    attr_reader :env_path, :settings

    def apply_env_overrides
      ConfigurationDefinitions.definitions.each do |name, definition|
        settings.public_send("#{name}=", ConfigurationDefinitions.env_value(definition, ENV))
      end
    end

    def secrets
      ConfigurationSecrets.new(
        settings: settings,
        env: ENV
      )
    end

    def load_env_file
      EnvFile.new(env_path).apply_to(ENV)
    end
  end
end

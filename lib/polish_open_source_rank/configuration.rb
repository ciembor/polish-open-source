# frozen_string_literal: true

require 'dry/configurable'

module PolishOpenSourceRank
  class Configuration
    extend Dry::Configurable

    APP_BASE_PATH_CONSTRUCTOR = proc { |value| normalize_app_base_path(value) }
    DATABASE_PATH_CONSTRUCTOR = proc { |value| value.delete_prefix('sqlite://') }

    DEFINITIONS = {
      github_token: { env: 'GITHUB_TOKEN', required: true },
      gitlab_token: { env: 'GITLAB_TOKEN' },
      codeberg_token: { env: 'CODEBERG_TOKEN' },
      database_path: {
        env: 'DATABASE_URL',
        default: 'sqlite://db/polish_open_source_rank.sqlite3',
        constructor: DATABASE_PATH_CONSTRUCTOR
      },
      requests_per_minute: { env: 'REQUESTS_PER_MINUTE', default: 60, constructor: proc(&:to_i) },
      github_base_url: { env: 'GITHUB_BASE_URL', default: 'https://api.github.com' },
      github_oauth_client_id: { env: 'GITHUB_OAUTH_CLIENT_ID', required: true },
      github_oauth_client_secret: { env: 'GITHUB_OAUTH_CLIENT_SECRET', required: true },
      discord_oauth_client_id: { env: 'DISCORD_OAUTH_CLIENT_ID', required: true },
      discord_oauth_client_secret: { env: 'DISCORD_OAUTH_CLIENT_SECRET', required: true },
      discord_bot_token: { env: 'DISCORD_BOT_TOKEN', required: true },
      discord_guild_id: { env: 'DISCORD_GUILD_ID', required: true },
      discord_invite_channel_id: { env: 'DISCORD_INVITE_CHANNEL_ID', required: true },
      session_secret: {
        env: 'SESSION_SECRET',
        default: 'local-development-session-secret-for-polish-open-source-rank-auth-flows'
      },
      gitlab_base_url: { env: 'GITLAB_BASE_URL', default: 'https://gitlab.com/api/v4' },
      codeberg_base_url: { env: 'CODEBERG_BASE_URL', default: 'https://codeberg.org/api/v1' },
      public_base_url: { env: 'BASE_URL', default: 'http://localhost:9292' },
      app_base_path: { env: 'APP_BASE_PATH', default: '', constructor: APP_BASE_PATH_CONSTRUCTOR }
    }.freeze

    DEFINITIONS.each do |name, definition|
      options = {}
      options[:default] = definition[:default] if definition.key?(:default)
      options[:constructor] = definition[:constructor] if definition.key?(:constructor)
      setting name, **options
    end

    def self.load(path = PolishOpenSourceRank.root.join('.env.local'))
      new(path).load
    end

    def self.normalize_app_base_path(raw_path)
      path = raw_path.to_s.strip
      return '' if path.empty? || path == '/'

      "/#{path.delete_prefix('/').delete_suffix('/')}"
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

    DEFINITIONS.each do |name, definition|
      define_method(name) do
        value = settings.public_send(name)
        return value unless definition[:required] && value.nil?

        ENV.fetch(definition.fetch(:env))
      end
    end

    private

    attr_reader :env_path, :settings

    def apply_env_overrides
      DEFINITIONS.each do |name, definition|
        value =
          if definition.key?(:default)
            ENV.fetch(definition.fetch(:env), definition.fetch(:default))
          else
            ENV.fetch(definition.fetch(:env), nil)
          end

        settings.public_send("#{name}=", value)
      end
    end

    def load_env_file
      return unless env_path.file?

      env_path.each_line(chomp: true) do |line|
        key, value = line.split('=', 2)
        ENV[key] ||= value if key && value && !key.empty?
      end
    end
  end
end

# frozen_string_literal: true

require 'dry/configurable'

module PolishOpenSourceRank
  class Configuration
    extend Dry::Configurable

    APP_BASE_PATH_CONSTRUCTOR = proc { |value| normalize_app_base_path(value) }
    DATABASE_PATH_CONSTRUCTOR = proc { |value| value.delete_prefix('sqlite://') }
    OPTIONAL_DATABASE_PATH_CONSTRUCTOR = proc { |value| value.to_s.delete_prefix('sqlite://') }
    INTEGER_CONSTRUCTOR = proc(&:to_i)
    FLOAT_CONSTRUCTOR = proc(&:to_f)
    MINIMUM_SESSION_SECRET_LENGTH = 64
    LOCAL_SESSION_SECRET = 'local-development-session-secret-for-polish-open-source-rank-auth-flows'

    DEFINITIONS = {
      rack_env: { env: 'RACK_ENV', default: 'development' },
      github_token: { env: 'GITHUB_TOKEN', required: true },
      gitlab_token: { env: 'GITLAB_TOKEN' },
      codeberg_token: { env: 'CODEBERG_TOKEN' },
      database_path: {
        env: 'DATABASE_URL',
        default: 'sqlite://db/polish_open_source_rank.sqlite3',
        constructor: DATABASE_PATH_CONSTRUCTOR
      },
      public_database_path: {
        env: 'PUBLIC_DATABASE_URL',
        constructor: OPTIONAL_DATABASE_PATH_CONSTRUCTOR
      },
      requests_per_minute: { env: 'REQUESTS_PER_MINUTE', default: 60, constructor: INTEGER_CONSTRUCTOR },
      http_open_timeout: { env: 'HTTP_OPEN_TIMEOUT', default: 5, constructor: INTEGER_CONSTRUCTOR },
      http_read_timeout: { env: 'HTTP_READ_TIMEOUT', default: 30, constructor: INTEGER_CONSTRUCTOR },
      http_write_timeout: { env: 'HTTP_WRITE_TIMEOUT', default: 30, constructor: INTEGER_CONSTRUCTOR },
      user_action_http_open_timeout: {
        env: 'USER_ACTION_HTTP_OPEN_TIMEOUT',
        default: 3,
        constructor: INTEGER_CONSTRUCTOR
      },
      user_action_http_read_timeout: {
        env: 'USER_ACTION_HTTP_READ_TIMEOUT',
        default: 10,
        constructor: INTEGER_CONSTRUCTOR
      },
      user_action_http_write_timeout: {
        env: 'USER_ACTION_HTTP_WRITE_TIMEOUT',
        default: 10,
        constructor: INTEGER_CONSTRUCTOR
      },
      npm_registry_requests_per_minute: {
        env: 'NPM_REGISTRY_REQUESTS_PER_MINUTE',
        default: 30,
        constructor: INTEGER_CONSTRUCTOR
      },
      rubygems_registry_requests_per_minute: {
        env: 'RUBYGEMS_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      crates_registry_requests_per_minute: {
        env: 'CRATES_REGISTRY_REQUESTS_PER_MINUTE',
        default: 10,
        constructor: INTEGER_CONSTRUCTOR
      },
      pypi_registry_requests_per_minute: {
        env: 'PYPI_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      hex_registry_requests_per_minute: {
        env: 'HEX_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      packagist_registry_requests_per_minute: {
        env: 'PACKAGIST_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      go_registry_requests_per_minute: {
        env: 'GO_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      homebrew_registry_requests_per_minute: {
        env: 'HOMEBREW_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      nuget_registry_requests_per_minute: {
        env: 'NUGET_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      maven_registry_requests_per_minute: {
        env: 'MAVEN_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      terraform_registry_requests_per_minute: {
        env: 'TERRAFORM_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      conan_registry_requests_per_minute: {
        env: 'CONAN_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      vcpkg_registry_requests_per_minute: {
        env: 'VCPKG_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      swiftpm_registry_requests_per_minute: {
        env: 'SWIFTPM_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      pub_registry_requests_per_minute: {
        env: 'PUB_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      apt_registry_requests_per_minute: {
        env: 'APT_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      rpm_registry_requests_per_minute: {
        env: 'RPM_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      nix_registry_requests_per_minute: {
        env: 'NIX_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      cran_registry_requests_per_minute: {
        env: 'CRAN_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      cpan_registry_requests_per_minute: {
        env: 'CPAN_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      hackage_registry_requests_per_minute: {
        env: 'HACKAGE_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      clojars_registry_requests_per_minute: {
        env: 'CLOJARS_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      julia_registry_requests_per_minute: {
        env: 'JULIA_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      conda_registry_requests_per_minute: {
        env: 'CONDA_REGISTRY_REQUESTS_PER_MINUTE',
        default: 20,
        constructor: INTEGER_CONSTRUCTOR
      },
      github_base_url: { env: 'GITHUB_BASE_URL', default: 'https://api.github.com' },
      github_oauth_client_id: { env: 'GITHUB_OAUTH_CLIENT_ID', required: true },
      github_oauth_client_secret: { env: 'GITHUB_OAUTH_CLIENT_SECRET', required: true },
      discord_oauth_client_id: { env: 'DISCORD_OAUTH_CLIENT_ID', required: true },
      discord_oauth_client_secret: { env: 'DISCORD_OAUTH_CLIENT_SECRET', required: true },
      discord_bot_token: { env: 'DISCORD_BOT_TOKEN', required: true },
      discord_guild_id: { env: 'DISCORD_GUILD_ID', required: true },
      discord_invite_channel_id: { env: 'DISCORD_INVITE_CHANNEL_ID', required: true },
      session_secret: { env: 'SESSION_SECRET' },
      gitlab_base_url: { env: 'GITLAB_BASE_URL', default: 'https://gitlab.com/api/v4' },
      codeberg_base_url: { env: 'CODEBERG_BASE_URL', default: 'https://codeberg.org/api/v1' },
      public_base_url: { env: 'BASE_URL', default: 'http://localhost:9292' },
      app_base_path: { env: 'APP_BASE_PATH', default: '', constructor: APP_BASE_PATH_CONSTRUCTOR },
      sentry_dsn: { env: 'SENTRY_DSN' },
      sentry_environment: { env: 'SENTRY_ENVIRONMENT' },
      sentry_release: { env: 'SENTRY_RELEASE' },
      sentry_traces_sample_rate: { env: 'SENTRY_TRACES_SAMPLE_RATE', default: 0.05, constructor: FLOAT_CONSTRUCTOR }
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
      next if name == :session_secret

      define_method(name) do
        value = settings.public_send(name)
        return value unless definition[:required] && value.nil?

        ENV.fetch(definition.fetch(:env))
      end
    end

    def session_secret
      value = settings.session_secret
      value = nil if value&.empty?
      return LOCAL_SESSION_SECRET if value.nil? && !production?

      value ||= ENV.fetch('SESSION_SECRET')
      production? ? validate_production_session_secret(value) : value
    end

    def public_database_path
      value = settings.public_database_path.to_s
      value.empty? ? database_path : value
    end

    def http_timeouts
      {
        open_timeout: http_open_timeout,
        read_timeout: http_read_timeout,
        write_timeout: http_write_timeout
      }
    end

    def user_action_http_timeouts
      {
        open_timeout: user_action_http_open_timeout,
        read_timeout: user_action_http_read_timeout,
        write_timeout: user_action_http_write_timeout
      }
    end

    def package_registry_request_limits
      package_registry_limit_keys.to_h do |key|
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

    def package_registry_limit_keys
      %i[
        npm rubygems crates pypi hex packagist go homebrew nuget maven terraform conan vcpkg swiftpm pub
        apt rpm nix cran cpan hackage clojars julia conda
      ]
    end

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

    def production?
      settings.rack_env == 'production'
    end

    def validate_production_session_secret(secret)
      secret.tap do
        next if secret.length >= MINIMUM_SESSION_SECRET_LENGTH

        raise ArgumentError,
              "SESSION_SECRET must be at least #{MINIMUM_SESSION_SECRET_LENGTH} characters in production"
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

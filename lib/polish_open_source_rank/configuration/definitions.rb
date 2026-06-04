# frozen_string_literal: true

require_relative 'auth_definitions'
require_relative 'package_registry_definitions'
require_relative 'request_definitions'

module PolishOpenSourceRank
  # Owns raw environment variable names, defaults, and parser choices for Configuration.
  module ConfigurationDefinitions
    INTEGER_CONSTRUCTOR = proc(&:to_i)
    NO_DEFAULT = Object.new.freeze

    def self.env_value(definition, env)
      env_key = definition.fetch(:env)
      return env.fetch(env_key, definition.fetch(:default)) if definition.key?(:default)

      env.fetch(env_key, nil)
    end

    def self.normalize_app_base_path(raw_path)
      path = raw_path.to_s.strip
      return '' if path.empty? || path == '/'

      "/#{path.delete_prefix('/').delete_suffix('/')}"
    end

    def self.definitions
      @definitions ||= definition_groups.reduce(&:merge).freeze
    end

    def self.definition_groups
      [
        runtime_settings,
        database_settings,
        request_settings,
        package_registry_settings,
        source_settings,
        auth_settings,
        public_web_settings,
        sentry_settings
      ]
    end
    private_class_method :definition_groups

    def self.runtime_settings
      { rack_env: { env: 'RACK_ENV', default: 'development' } }
    end
    private_class_method :runtime_settings

    def self.database_settings
      {
        database_path: {
          env: 'DATABASE_URL',
          default: 'sqlite://db/polish_open_source_rank.sqlite3',
          constructor: proc { |value| value.delete_prefix('sqlite://') }
        },
        public_database_path: {
          env: 'PUBLIC_DATABASE_URL',
          constructor: proc { |value| value.to_s.delete_prefix('sqlite://') }
        }
      }
    end
    private_class_method :database_settings

    def self.request_settings
      RequestConfigurationDefinitions.definitions(constructor: INTEGER_CONSTRUCTOR)
    end
    private_class_method :request_settings

    def self.package_registry_settings
      PackageRegistryConfigurationDefinitions.definitions(constructor: INTEGER_CONSTRUCTOR)
    end
    private_class_method :package_registry_settings

    def self.source_settings
      {
        github_token: { env: 'GITHUB_TOKEN', required: true },
        gitlab_token: env('GITLAB_TOKEN'),
        codeberg_token: env('CODEBERG_TOKEN'),
        github_base_url: env('GITHUB_BASE_URL', default: 'https://api.github.com'),
        gitlab_base_url: env('GITLAB_BASE_URL', default: 'https://gitlab.com/api/v4'),
        codeberg_base_url: env('CODEBERG_BASE_URL', default: 'https://codeberg.org/api/v1')
      }
    end
    private_class_method :source_settings

    def self.auth_settings
      AuthConfigurationDefinitions.definitions
    end
    private_class_method :auth_settings

    def self.public_web_settings
      {
        public_base_url: env('BASE_URL', default: 'http://localhost:9292'),
        app_base_path: {
          env: 'APP_BASE_PATH',
          default: '',
          constructor: proc { |value| normalize_app_base_path(value) }
        }
      }
    end
    private_class_method :public_web_settings

    def self.sentry_settings
      {
        sentry_dsn: env('SENTRY_DSN'),
        sentry_environment: env('SENTRY_ENVIRONMENT'),
        sentry_release: env('SENTRY_RELEASE'),
        sentry_traces_sample_rate: {
          env: 'SENTRY_TRACES_SAMPLE_RATE',
          default: 0.05,
          constructor: proc(&:to_f)
        }
      }
    end
    private_class_method :sentry_settings

    def self.env(env_key, default: NO_DEFAULT)
      definition = { env: env_key }
      definition[:default] = default unless default.equal?(NO_DEFAULT)
      definition
    end
    private_class_method :env
  end
end

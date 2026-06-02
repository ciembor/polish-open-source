# frozen_string_literal: true

module PolishOpenSourceRank
  # Resolves local and production-only authentication secrets for Configuration.
  class ConfigurationSecrets
    MINIMUM_SESSION_SECRET_LENGTH = 64
    MINIMUM_INTERNAL_BASIC_AUTH_PASSWORD_LENGTH = 32
    LOCAL_SESSION_SECRET = 'local-development-session-secret-for-polish-open-source-rank-auth-flows'
    LOCAL_INTERNAL_BASIC_AUTH_USERNAME = 'internal'
    LOCAL_INTERNAL_BASIC_AUTH_PASSWORD = 'local-internal-basic-auth-password'

    def initialize(settings:, env:)
      @settings = settings
      @env = env
    end

    def session_secret
      secret = configured_secret(session_secret_value)
      return LOCAL_SESSION_SECRET if blank_local_secret?(secret)

      secret = env.fetch('SESSION_SECRET') if secret.empty?
      production? ? validate_session_secret(secret) : secret
    end

    def internal_basic_auth
      username = internal_basic_auth_username.to_s
      password = internal_basic_auth_password.to_s
      return local_internal_basic_auth if username.empty? && password.empty? && !production?

      validate_internal_basic_auth(username, password)
      { username: username, password: password }
    end

    private

    attr_reader :settings, :env

    def session_secret_value
      settings.session_secret
    end

    def internal_basic_auth_username
      settings.internal_basic_auth_username
    end

    def internal_basic_auth_password
      settings.internal_basic_auth_password
    end

    def configured_secret(value)
      value.to_s
    end

    def blank_local_secret?(secret)
      secret.empty? && !production?
    end

    def production?
      settings.rack_env == 'production'
    end

    def validate_session_secret(secret)
      return secret if secret.length >= MINIMUM_SESSION_SECRET_LENGTH

      raise ArgumentError, "SESSION_SECRET must be at least #{MINIMUM_SESSION_SECRET_LENGTH} characters in production"
    end

    def local_internal_basic_auth
      {
        username: LOCAL_INTERNAL_BASIC_AUTH_USERNAME,
        password: LOCAL_INTERNAL_BASIC_AUTH_PASSWORD
      }
    end

    def validate_internal_basic_auth(username, password)
      raise ArgumentError, 'INTERNAL_BASIC_AUTH_USERNAME must be configured' if username.empty?

      return unless password.length < MINIMUM_INTERNAL_BASIC_AUTH_PASSWORD_LENGTH

      raise ArgumentError,
            "INTERNAL_BASIC_AUTH_PASSWORD must be at least #{MINIMUM_INTERNAL_BASIC_AUTH_PASSWORD_LENGTH} characters"
    end
  end
end

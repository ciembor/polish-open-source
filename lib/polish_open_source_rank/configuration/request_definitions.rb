# frozen_string_literal: true

module PolishOpenSourceRank
  # Owns general HTTP and request-rate environment definitions.
  module RequestConfigurationDefinitions
    SETTINGS = {
      requests_per_minute: ['REQUESTS_PER_MINUTE', 60],
      http_open_timeout: ['HTTP_OPEN_TIMEOUT', 5],
      http_read_timeout: ['HTTP_READ_TIMEOUT', 30],
      http_write_timeout: ['HTTP_WRITE_TIMEOUT', 30],
      user_action_http_open_timeout: ['USER_ACTION_HTTP_OPEN_TIMEOUT', 3],
      user_action_http_read_timeout: ['USER_ACTION_HTTP_READ_TIMEOUT', 10],
      user_action_http_write_timeout: ['USER_ACTION_HTTP_WRITE_TIMEOUT', 10]
    }.freeze

    def self.definitions(constructor:)
      SETTINGS.to_h do |name, (env_key, default)|
        [name, { env: env_key, default: default, constructor: constructor }]
      end
    end
  end
end

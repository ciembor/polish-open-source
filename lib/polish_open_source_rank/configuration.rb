# frozen_string_literal: true

module PolishOpenSourceRank
  class Configuration
    DEFAULT_DATABASE_PATH = 'db/polish_open_source_rank.sqlite3'
    DEFAULT_REQUESTS_PER_MINUTE = 60

    def self.load(path = PolishOpenSourceRank.root.join('.env.local'))
      new(path).load
    end

    def initialize(env_path)
      @env_path = env_path
    end

    def load
      load_env_file
      self
    end

    def github_token
      ENV.fetch('GITHUB_TOKEN')
    end

    def gitlab_token
      ENV.fetch('GITLAB_TOKEN', nil)
    end

    def codeberg_token
      ENV.fetch('CODEBERG_TOKEN', nil)
    end

    def database_path
      database_url = ENV.fetch('DATABASE_URL', "sqlite://#{DEFAULT_DATABASE_PATH}")
      database_url.delete_prefix('sqlite://')
    end

    def requests_per_minute
      ENV.fetch('REQUESTS_PER_MINUTE', DEFAULT_REQUESTS_PER_MINUTE).to_i
    end

    def github_base_url
      ENV.fetch('GITHUB_BASE_URL', 'https://api.github.com')
    end

    def gitlab_base_url
      ENV.fetch('GITLAB_BASE_URL', 'https://gitlab.com/api/v4')
    end

    def codeberg_base_url
      ENV.fetch('CODEBERG_BASE_URL', 'https://codeberg.org/api/v1')
    end

    def public_base_url
      ENV.fetch('BASE_URL', 'http://localhost:9292')
    end

    def app_base_path
      raw_path = ENV.fetch('APP_BASE_PATH', '').strip
      return '' if raw_path.empty? || raw_path == '/'

      "/#{raw_path.delete_prefix('/').delete_suffix('/')}"
    end

    private

    attr_reader :env_path

    def load_env_file
      return unless env_path.file?

      env_path.each_line(chomp: true) do |line|
        key, value = line.split('=', 2)
        ENV[key] ||= value if key && value && !key.empty?
      end
    end
  end
end

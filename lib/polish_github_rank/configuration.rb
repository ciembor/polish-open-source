# frozen_string_literal: true

module PolishGithubRank
  class Configuration
    DEFAULT_DATABASE_PATH = "db/polish_github_rank.sqlite3"
    DEFAULT_REQUESTS_PER_MINUTE = 45

    def self.load(path = PolishGithubRank.root.join(".env.local"))
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
      ENV.fetch("GITHUB_TOKEN")
    end

    def database_path
      database_url = ENV.fetch("DATABASE_URL", "sqlite://#{DEFAULT_DATABASE_PATH}")
      database_url.delete_prefix("sqlite://")
    end

    def requests_per_minute
      ENV.fetch("REQUESTS_PER_MINUTE", DEFAULT_REQUESTS_PER_MINUTE).to_i
    end

    private

    attr_reader :env_path

    def load_env_file
      return unless env_path.file?

      env_path.each_line(chomp: true) do |line|
        key, value = line.split("=", 2)
        ENV[key] ||= value if key && value && !key.empty?
      end
    end
  end
end


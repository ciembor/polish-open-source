# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'time'
require 'zeitwerk'

module PolishOpenSourceRank
  def self.root
    Pathname(__dir__).parent
  end

  class LoaderInflector < Zeitwerk::Inflector
    TOKEN_OVERRIDES = {
      'cli' => 'CLI',
      'github' => 'GitHub',
      'gitlab' => 'GitLab',
      'oauth' => 'OAuth',
      'sqlite' => 'SQLite'
    }.freeze

    BASENAME_OVERRIDES = {
      'oauth_http' => 'OAuthHTTP',
      'py_pi_registry_client' => 'PyPIRegistryClient',
      'registry_http_client' => 'RegistryHTTPClient'
    }.freeze

    PATH_OVERRIDES = {
      'infrastructure/codeberg/client.rb' => 'CodebergClient',
      'infrastructure/codeberg/gateway.rb' => 'CodebergGateway',
      'infrastructure/github/client.rb' => 'GitHubClient',
      'infrastructure/github/gateway.rb' => 'GitHubGateway',
      'infrastructure/gitlab/client.rb' => 'GitLabClient',
      'infrastructure/gitlab/gateway.rb' => 'GitLabGateway'
    }.freeze

    def camelize(basename, abspath)
      PATH_OVERRIDES.fetch(relative_path(abspath)) do
        BASENAME_OVERRIDES.fetch(basename) do
          basename.split('_').map { |part| TOKEN_OVERRIDES.fetch(part) { super(part, abspath) } }.join
        end
      end
    end

    private

    def relative_path(abspath)
      prefix = "#{PolishOpenSourceRank.root.join('lib/polish_open_source_rank')}/"
      abspath.delete_prefix(prefix)
    end
  end

  def self.loader
    @loader ||= begin
      loader = Zeitwerk::Loader.new
      loader.inflector = LoaderInflector.new
      loader.push_dir(root.join('lib/polish_open_source_rank').to_s, namespace: self)
      loader.collapse(root.join('lib/polish_open_source_rank/infrastructure/github').to_s)
      loader.collapse(root.join('lib/polish_open_source_rank/infrastructure/gitlab').to_s)
      loader.collapse(root.join('lib/polish_open_source_rank/infrastructure/codeberg').to_s)
      loader.setup
      loader
    end
  end
end

PolishOpenSourceRank.loader

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Configuration do
  around do |example|
    keys = %w[
      GITHUB_TOKEN GITLAB_TOKEN CODEBERG_TOKEN DATABASE_URL PUBLIC_DATABASE_URL REQUESTS_PER_MINUTE
      GITHUB_BASE_URL GITLAB_BASE_URL CODEBERG_BASE_URL BASE_URL
      DISCORD_INVITE_CHANNEL_ID GITHUB_OAUTH_CLIENT_ID
      GITHUB_OAUTH_CLIENT_SECRET DISCORD_OAUTH_CLIENT_ID DISCORD_OAUTH_CLIENT_SECRET
      DISCORD_BOT_TOKEN DISCORD_GUILD_ID
      HTTP_OPEN_TIMEOUT HTTP_READ_TIMEOUT HTTP_WRITE_TIMEOUT
      USER_ACTION_HTTP_OPEN_TIMEOUT USER_ACTION_HTTP_READ_TIMEOUT USER_ACTION_HTTP_WRITE_TIMEOUT
      RACK_ENV SESSION_SECRET
      INTERNAL_BASIC_AUTH_USERNAME INTERNAL_BASIC_AUTH_PASSWORD
      GOOGLE_ANALYTICS_MEASUREMENT_ID
      EMPTY_VALUE
      SENTRY_DSN SENTRY_ENVIRONMENT SENTRY_RELEASE SENTRY_TRACES_SAMPLE_RATE
      NPM_REGISTRY_REQUESTS_PER_MINUTE RUBYGEMS_REGISTRY_REQUESTS_PER_MINUTE
      CRATES_REGISTRY_REQUESTS_PER_MINUTE PYPI_REGISTRY_REQUESTS_PER_MINUTE
      HEX_REGISTRY_REQUESTS_PER_MINUTE PACKAGIST_REGISTRY_REQUESTS_PER_MINUTE
      GO_REGISTRY_REQUESTS_PER_MINUTE HOMEBREW_REGISTRY_REQUESTS_PER_MINUTE
      NUGET_REGISTRY_REQUESTS_PER_MINUTE MAVEN_REGISTRY_REQUESTS_PER_MINUTE
      TERRAFORM_REGISTRY_REQUESTS_PER_MINUTE CONAN_REGISTRY_REQUESTS_PER_MINUTE
      VCPKG_REGISTRY_REQUESTS_PER_MINUTE SWIFTPM_REGISTRY_REQUESTS_PER_MINUTE
      PUB_REGISTRY_REQUESTS_PER_MINUTE APT_REGISTRY_REQUESTS_PER_MINUTE
      RPM_REGISTRY_REQUESTS_PER_MINUTE NIX_REGISTRY_REQUESTS_PER_MINUTE
      CRAN_REGISTRY_REQUESTS_PER_MINUTE CPAN_REGISTRY_REQUESTS_PER_MINUTE
      HACKAGE_REGISTRY_REQUESTS_PER_MINUTE CLOJARS_REGISTRY_REQUESTS_PER_MINUTE
      JULIA_REGISTRY_REQUESTS_PER_MINUTE CONDA_REGISTRY_REQUESTS_PER_MINUTE
    ]
    old_values = keys.to_h { |key| [key, ENV.fetch(key, nil)] }
    keys.each { |key| ENV.delete(key) }
    example.run
  ensure
    old_values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  it 'loads local environment files and exposes typed settings' do
    path = Pathname(File.join(Dir.mktmpdir, '.env.local'))
    path.write(<<~ENV_FILE)
      GITHUB_TOKEN=secret
      DATABASE_URL=sqlite://tmp/test.sqlite3
      REQUESTS_PER_MINUTE=33
      GITHUB_BASE_URL=https://github.test
      GITLAB_TOKEN=gitlab-secret
      GITLAB_BASE_URL=https://gitlab.test/api/v4
      CODEBERG_TOKEN=codeberg-secret
      CODEBERG_BASE_URL=https://codeberg.test/api/v1
      BASE_URL=https://rank.test
    ENV_FILE

    configuration = described_class.load(path)

    expect(configuration.github_token).to eq('secret')
    expect(configuration.database_path).to eq('tmp/test.sqlite3')
    expect(configuration.requests_per_minute).to eq(33)
    expect(configuration.github_base_url).to eq('https://github.test')
    expect(configuration.gitlab_token).to eq('gitlab-secret')
    expect(configuration.gitlab_base_url).to eq('https://gitlab.test/api/v4')
    expect(configuration.codeberg_token).to eq('codeberg-secret')
    expect(configuration.codeberg_base_url).to eq('https://codeberg.test/api/v1')
    expect(configuration.public_base_url).to eq('https://rank.test')
    expect(configuration.app_base_path).to eq('')
  end

  it 'parses local environment files with comments, exports, and quoted values' do
    path = Pathname(File.join(Dir.mktmpdir, '.env.local'))
    path.write(<<~ENV_FILE)
      # local development secrets
      export GITHUB_TOKEN="quoted secret"
      DATABASE_URL='sqlite://tmp/quoted.sqlite3'
      BASE_URL=https://rank.test # inline comment
      GITHUB_BASE_URL=https://github.test/path#fragment
      EMPTY_VALUE=
    ENV_FILE

    configuration = described_class.load(path)

    expect(configuration.github_token).to eq('quoted secret')
    expect(configuration.database_path).to eq('tmp/quoted.sqlite3')
    expect(configuration.public_base_url).to eq('https://rank.test')
    expect(configuration.github_base_url).to eq('https://github.test/path#fragment')
    expect(ENV.fetch('EMPTY_VALUE')).to eq('')
  end

  it 'exposes the configured Discord invite channel' do
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'discord-channel'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.discord_invite_channel_id).to eq('discord-channel')
  end

  it 'uses stable defaults without an env file' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.database_path).to eq('db/polish_open_source_rank.sqlite3')
    expect(configuration.public_database_path).to eq('db/polish_open_source_rank.sqlite3')
    expect(configuration.requests_per_minute).to eq(60)
    expect(configuration.github_base_url).to eq('https://api.github.com')
    expect(configuration.gitlab_token).to be_nil
    expect(configuration.gitlab_base_url).to eq('https://gitlab.com/api/v4')
    expect(configuration.codeberg_token).to be_nil
    expect(configuration.codeberg_base_url).to eq('https://codeberg.org/api/v1')
    expect(configuration.public_base_url).to eq('http://localhost:9292')
    expect(configuration.app_base_path).to eq('')
  end

  it 'applies required, optional, defaulted, and transformed env definitions through the public API' do
    ENV['GITHUB_TOKEN'] = 'required-secret'
    ENV['DATABASE_URL'] = 'sqlite://tmp/transformed.sqlite3'
    ENV['REQUESTS_PER_MINUTE'] = '44'
    ENV['APP_BASE_PATH'] = 'rank/'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.github_token).to eq('required-secret')
    expect(configuration.gitlab_token).to be_nil
    expect(configuration.github_base_url).to eq('https://api.github.com')
    expect(configuration.database_path).to eq('tmp/transformed.sqlite3')
    expect(configuration.requests_per_minute).to eq(44)
    expect(configuration.app_base_path).to eq('/rank')
  end

  it 'exposes the optional Google Analytics measurement id' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.google_analytics_measurement_id).to be_nil

    ENV['GOOGLE_ANALYTICS_MEASUREMENT_ID'] = 'G-ABC123DEF4'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.google_analytics_measurement_id).to eq('G-ABC123DEF4')
  end

  it 'keeps Sentry disabled without a DSN' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.sentry_enabled?).to be(false)
    expect(configuration.sentry_runtime_environment).to eq('development')
  end

  it 'uses an optional public database path for read-only public pages' do
    ENV['DATABASE_URL'] = 'sqlite://tmp/write.sqlite3'
    ENV['PUBLIC_DATABASE_URL'] = 'sqlite://tmp/public.sqlite3'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.database_path).to eq('tmp/write.sqlite3')
    expect(configuration.public_database_path).to eq('tmp/public.sqlite3')
    expect(configuration.database_paths).to have_attributes(
      primary: 'tmp/write.sqlite3',
      public: 'tmp/public.sqlite3'
    )
  end

  it 'uses stable local HTTP and session defaults without an env file' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.http_open_timeout).to eq(5)
    expect(configuration.http_read_timeout).to eq(30)
    expect(configuration.http_write_timeout).to eq(30)
    expect(configuration.http_timeouts).to eq(open_timeout: 5, read_timeout: 30, write_timeout: 30)
    expect(configuration.session_secret).to eq(
      'local-development-session-secret-for-polish-open-source-rank-auth-flows'
    )
    expect(configuration.internal_basic_auth).to eq(
      username: 'internal',
      password: 'local-internal-basic-auth-password'
    )
  end

  it 'exposes grouped network, OAuth, Discord, and database settings' do
    ENV['GITHUB_OAUTH_CLIENT_ID'] = 'github-client'
    ENV['GITHUB_OAUTH_CLIENT_SECRET'] = 'github-secret'
    ENV['DISCORD_OAUTH_CLIENT_ID'] = 'discord-client'
    ENV['DISCORD_OAUTH_CLIENT_SECRET'] = 'discord-secret'
    ENV['DISCORD_BOT_TOKEN'] = 'discord-bot'
    ENV['DISCORD_GUILD_ID'] = 'discord-guild'
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'discord-invite-channel'
    ENV['USER_ACTION_HTTP_OPEN_TIMEOUT'] = '2'
    ENV['USER_ACTION_HTTP_READ_TIMEOUT'] = '8'
    ENV['USER_ACTION_HTTP_WRITE_TIMEOUT'] = '9'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.network.source_api.to_h).to eq(open_timeout: 5, read_timeout: 30, write_timeout: 30)
    expect(configuration.network.user_action.to_h).to eq(open_timeout: 2, read_timeout: 8, write_timeout: 9)
    expect(configuration.oauth).to have_attributes(
      github_client_id: 'github-client',
      github_client_secret: 'github-secret',
      discord_client_id: 'discord-client',
      discord_client_secret: 'discord-secret'
    )
    expect(configuration.discord).to have_attributes(
      bot_token: 'discord-bot',
      guild_id: 'discord-guild',
      invite_channel_id: 'discord-invite-channel'
    )
    expect(configuration.database_paths).to have_attributes(
      primary: 'db/polish_open_source_rank.sqlite3',
      public: 'db/polish_open_source_rank.sqlite3'
    )
  end

  it 'exposes configured internal Basic Auth credentials' do
    ENV['INTERNAL_BASIC_AUTH_USERNAME'] = 'ops'
    ENV['INTERNAL_BASIC_AUTH_PASSWORD'] = 'production-internal-basic-auth-secret'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.internal_basic_auth).to eq(
      username: 'ops',
      password: 'production-internal-basic-auth-secret'
    )
  end

  it 'normalizes a configured base path' do
    ENV['APP_BASE_PATH'] = '/polish-open-source-rank/'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.app_base_path).to eq('/polish-open-source-rank')
  end

  it 'keeps required env access lazy until the value is read' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.github_oauth_client_id }.to raise_error(KeyError)

    ENV['GITHUB_OAUTH_CLIENT_ID'] = 'github-client-id'

    expect(configuration.github_oauth_client_id).to eq('github-client-id')
  end

  it 'does not mutate the class-level config while loading an instance' do
    path = Pathname(File.join(Dir.mktmpdir, '.env.local'))
    path.write("BASE_URL=https://rank.test\n")

    configuration = described_class.load(path)

    expect(configuration.public_base_url).to eq('https://rank.test')
    expect(described_class.config.public_base_url).to eq('http://localhost:9292')
  end

  it 'reads configured HTTP timeouts as integers' do
    ENV['HTTP_OPEN_TIMEOUT'] = '7'
    ENV['HTTP_READ_TIMEOUT'] = '31'
    ENV['HTTP_WRITE_TIMEOUT'] = '29'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.http_open_timeout).to eq(7)
    expect(configuration.http_read_timeout).to eq(31)
    expect(configuration.http_write_timeout).to eq(29)
  end

  it 'exposes Sentry configuration without requiring it locally' do
    ENV['RACK_ENV'] = 'production'
    ENV['SENTRY_DSN'] = 'https://public@example.ingest.sentry.io/1'
    ENV['SENTRY_ENVIRONMENT'] = 'production'
    ENV['SENTRY_RELEASE'] = 'abc123'
    ENV['SENTRY_TRACES_SAMPLE_RATE'] = '0.25'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.sentry_enabled?).to be(true)
    expect(configuration.sentry_dsn).to eq('https://public@example.ingest.sentry.io/1')
    expect(configuration.sentry_runtime_environment).to eq('production')
    expect(configuration.sentry_release).to eq('abc123')
    expect(configuration.sentry_traces_sample_rate).to eq(0.25)
  end

  it 'exposes conservative package registry request limits' do
    ENV['NPM_REGISTRY_REQUESTS_PER_MINUTE'] = '11'
    ENV['CRATES_REGISTRY_REQUESTS_PER_MINUTE'] = '7'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.npm_registry_requests_per_minute).to eq(11)
    expect(configuration.crates_registry_requests_per_minute).to eq(7)
    expect(configuration.package_registry_request_limits).to include(expected_package_registry_limits)
  end

  def expected_package_registry_limits
    {
      npm: 11,
      rubygems: 20,
      crates: 7,
      pypi: 20,
      hex: 20,
      packagist: 20,
      go: 20,
      homebrew: 20,
      nuget: 20,
      maven: 20,
      terraform: 20,
      conan: 20,
      vcpkg: 20,
      swiftpm: 20,
      pub: 20,
      apt: 20,
      rpm: 20,
      nix: 20,
      cran: 20,
      cpan: 20,
      hackage: 20,
      clojars: 20,
      julia: 20,
      conda: 20
    }
  end

  it 'requires a session secret in production' do
    ENV['RACK_ENV'] = 'production'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.session_secret }.to raise_error(KeyError)

    ENV['SESSION_SECRET'] = 'production-session-secret-for-polish-open-source-rank-auth-flows-2026'

    expect(configuration.session_secret).to eq(
      'production-session-secret-for-polish-open-source-rank-auth-flows-2026'
    )
  end

  it 'rejects short production session secrets' do
    ENV['RACK_ENV'] = 'production'
    ENV['SESSION_SECRET'] = 'short-production-secret'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.session_secret }.to raise_error(
      ArgumentError,
      'SESSION_SECRET must be at least 64 characters in production'
    )
  end

  it 'requires strong internal Basic Auth credentials in production' do
    ENV['RACK_ENV'] = 'production'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.internal_basic_auth }.to raise_error(
      ArgumentError,
      'INTERNAL_BASIC_AUTH_USERNAME must be configured'
    )

    ENV['INTERNAL_BASIC_AUTH_USERNAME'] = 'ops'
    ENV['INTERNAL_BASIC_AUTH_PASSWORD'] = 'short'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.internal_basic_auth }.to raise_error(
      ArgumentError,
      'INTERNAL_BASIC_AUTH_PASSWORD must be at least 32 characters'
    )
  end
end

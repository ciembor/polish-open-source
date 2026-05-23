# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Configuration do
  around do |example|
    keys = %w[
      GITHUB_TOKEN GITLAB_TOKEN CODEBERG_TOKEN DATABASE_URL REQUESTS_PER_MINUTE
      GITHUB_BASE_URL GITLAB_BASE_URL CODEBERG_BASE_URL BASE_URL
      DISCORD_INVITE_CHANNEL_ID GITHUB_OAUTH_CLIENT_ID
      HTTP_OPEN_TIMEOUT HTTP_READ_TIMEOUT HTTP_WRITE_TIMEOUT RACK_ENV SESSION_SECRET
      NPM_REGISTRY_REQUESTS_PER_MINUTE RUBYGEMS_REGISTRY_REQUESTS_PER_MINUTE
      CRATES_REGISTRY_REQUESTS_PER_MINUTE PYPI_REGISTRY_REQUESTS_PER_MINUTE
      HEX_REGISTRY_REQUESTS_PER_MINUTE PACKAGIST_REGISTRY_REQUESTS_PER_MINUTE
      GO_REGISTRY_REQUESTS_PER_MINUTE
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

  it 'exposes the configured Discord invite channel' do
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'discord-channel'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.discord_invite_channel_id).to eq('discord-channel')
  end

  it 'uses stable defaults without an env file' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.database_path).to eq('db/polish_open_source_rank.sqlite3')
    expect(configuration.requests_per_minute).to eq(60)
    expect(configuration.github_base_url).to eq('https://api.github.com')
    expect(configuration.gitlab_token).to be_nil
    expect(configuration.gitlab_base_url).to eq('https://gitlab.com/api/v4')
    expect(configuration.codeberg_token).to be_nil
    expect(configuration.codeberg_base_url).to eq('https://codeberg.org/api/v1')
    expect(configuration.public_base_url).to eq('http://localhost:9292')
    expect(configuration.app_base_path).to eq('')
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

  it 'exposes conservative package registry request limits' do
    ENV['NPM_REGISTRY_REQUESTS_PER_MINUTE'] = '11'
    ENV['CRATES_REGISTRY_REQUESTS_PER_MINUTE'] = '7'

    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.npm_registry_requests_per_minute).to eq(11)
    expect(configuration.crates_registry_requests_per_minute).to eq(7)
    expect(configuration.package_registry_request_limits).to include(
      npm: 11,
      rubygems: 20,
      crates: 7,
      pypi: 20,
      hex: 20,
      packagist: 20,
      go: 20
    )
  end

  it 'requires a session secret in production' do
    ENV['RACK_ENV'] = 'production'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect { configuration.session_secret }.to raise_error(KeyError)

    ENV['SESSION_SECRET'] = 'production-secret'

    expect(configuration.session_secret).to eq('production-secret')
  end
end

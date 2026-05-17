# frozen_string_literal: true

RSpec.describe PolishGithubRank::Configuration do
  around do |example|
    keys = %w[
      GITHUB_TOKEN GITLAB_TOKEN CODEBERG_TOKEN DATABASE_URL REQUESTS_PER_MINUTE
      GITHUB_BASE_URL GITLAB_BASE_URL CODEBERG_BASE_URL BASE_URL
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

  it 'uses stable defaults without an env file' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.database_path).to eq('db/polish_github_rank.sqlite3')
    expect(configuration.requests_per_minute).to eq(25)
    expect(configuration.github_base_url).to eq('https://api.github.com')
    expect(configuration.gitlab_token).to be_nil
    expect(configuration.gitlab_base_url).to eq('https://gitlab.com/api/v4')
    expect(configuration.codeberg_token).to be_nil
    expect(configuration.codeberg_base_url).to eq('https://codeberg.org/api/v1')
    expect(configuration.public_base_url).to eq('http://localhost:9292')
    expect(configuration.app_base_path).to eq('')
  end

  it 'normalizes a configured base path' do
    ENV['APP_BASE_PATH'] = '/polish-github-rank/'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.app_base_path).to eq('/polish-github-rank')
  end
end

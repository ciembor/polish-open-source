# frozen_string_literal: true

RSpec.describe PolishGithubRank::Configuration do
  around do |example|
    keys = %w[GITHUB_TOKEN DATABASE_URL REQUESTS_PER_MINUTE GITHUB_BASE_URL BASE_URL]
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
      BASE_URL=https://rank.test
    ENV_FILE

    configuration = described_class.load(path)

    expect(configuration.github_token).to eq('secret')
    expect(configuration.database_path).to eq('tmp/test.sqlite3')
    expect(configuration.requests_per_minute).to eq(33)
    expect(configuration.github_base_url).to eq('https://github.test')
    expect(configuration.public_base_url).to eq('https://rank.test')
    expect(configuration.app_base_path).to eq('')
  end

  it 'uses stable defaults without an env file' do
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.database_path).to eq('db/polish_github_rank.sqlite3')
    expect(configuration.requests_per_minute).to eq(25)
    expect(configuration.github_base_url).to eq('https://api.github.com')
    expect(configuration.public_base_url).to eq('http://localhost:9292')
    expect(configuration.app_base_path).to eq('')
  end

  it 'normalizes a configured base path' do
    ENV['APP_BASE_PATH'] = '/polish-github-rank/'
    configuration = described_class.load(Pathname(File.join(Dir.mktmpdir, 'missing.env')))

    expect(configuration.app_base_path).to eq('/polish-github-rank')
  end
end

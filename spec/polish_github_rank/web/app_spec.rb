# frozen_string_literal: true

RSpec.describe PolishGithubRank::Web::App do
  around do |example|
    old_database_url = ENV.fetch('DATABASE_URL', nil)
    old_base_url = ENV.fetch('BASE_URL', nil)
    ENV['BASE_URL'] = 'https://rank.example'
    example.run
  ensure
    ENV['DATABASE_URL'] = old_database_url
    ENV['BASE_URL'] = old_base_url
  end

  it 'renders the Poland ranking with SEO metadata' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Polska GitHub ranking</title>')
    expect(response.body).to include('rel="canonical" href="https://rank.example/"')
    expect(response.body).to include('alice/app')
    expect(response.body).to include('application/ld+json')
  end

  it 'renders city rankings and empty databases' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    response = Rack::MockRequest.new(described_class).get('/locations/krakow')

    expect(response.status).to eq(200)
    expect(response.body).to include('Kraków')
    expect(response.body).to include('Brak danych rankingowych')
  end

  it 'serves health checks and 404 pages' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    expect(Rack::MockRequest.new(described_class).get('/healthz').body).to eq('ok')
    expect(Rack::MockRequest.new(described_class).get('/locations/unknown').status).to eq(404)
  end

  def seed_database
    path = empty_database
    store = PolishGithubRank::Infrastructure::SQLiteStore.new(path).migrate!
    period = PolishGithubRank::Application::MonthPeriod.parse('2026-04')

    store.upsert_user(user_attributes)
    store.record_user_stats(user_stats(period))
    store.upsert_repository(repository_attributes)
    store.record_repository_stats(repository_stats(period))
    path
  end

  def empty_database
    File.join(Dir.mktmpdir, 'web.sqlite3')
  end

  def user_attributes
    {
      github_id: 1,
      login: 'alice',
      name: 'Alice',
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: 'alice@example.com',
      homepage: 'https://alice.example',
      html_url: 'https://github.com/alice',
      avatar_url: nil
    }
  end

  def user_stats(period)
    {
      period_start: period.start_date.to_s,
      user_github_id: 1,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: 12_345,
      monthly_stars_delta: 5,
      public_activity_count: 8
    }
  end

  def repository_attributes
    {
      github_id: 10,
      owner_github_id: 1,
      owner_login: 'alice',
      name: 'app',
      full_name: 'alice/app',
      description: 'Nice Ruby app',
      html_url: 'https://github.com/alice/app',
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false
    }
  end

  def repository_stats(period)
    {
      period_start: period.start_date.to_s,
      repository_github_id: 10,
      owner_github_id: 1,
      owner_login: 'alice',
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: 12_345,
      monthly_stars_delta: 5
    }
  end
end

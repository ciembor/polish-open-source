# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::App do
  around do |example|
    old_database_url = ENV.fetch('DATABASE_URL', nil)
    old_base_url = ENV.fetch('BASE_URL', nil)
    old_app_base_path = ENV.fetch('APP_BASE_PATH', nil)
    ENV['BASE_URL'] = 'https://rank.example'
    ENV.delete('APP_BASE_PATH')
    example.run
  ensure
    ENV['DATABASE_URL'] = old_database_url
    ENV['BASE_URL'] = old_base_url
    ENV['APP_BASE_PATH'] = old_app_base_path
  end

  it 'renders the Poland ranking with SEO metadata' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Poland open-source ranking</title>')
    expect(response.body).to include('rel="canonical" href="https://rank.example/latest"')
    expect(response.body).to include('alice/app')
    expect(response.body).to include('href="/latest/users/top"')
    expect(response.body).to include('See top 100')
    expect(response.body).to include('href="/editions"')
    expect(response.body).to include('application/ld+json')
  end

  it 'renders city rankings and empty databases' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    response = Rack::MockRequest.new(described_class).get('/locations/krakow')

    expect(response.status).to eq(200)
    expect(response.body).to include('Kraków')
    expect(response.body).to include('No ranking data')
    expect(response.body).to include('More cities')
  end

  it 'renders rankings for completed month slugs' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    latest_response = Rack::MockRequest.new(described_class).get('/latest')
    latest_city_response = Rack::MockRequest.new(described_class).get('/latest/locations/krakow')
    response = Rack::MockRequest.new(described_class).get('/2026-04/locations/krakow')
    month_response = Rack::MockRequest.new(described_class).get('/2026-04')

    expect(latest_response.status).to eq(200)
    expect(latest_city_response.status).to eq(200)
    expect(response.status).to eq(200)
    expect(month_response.status).to eq(200)
    expect(response.body).to include('alice/app')
    expect(response.body).to include('rel="canonical" href="https://rank.example/2026-04/locations/krakow"')
  end

  it 'renders explicit month slugs while the snapshot is still running' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    latest_response = Rack::MockRequest.new(described_class).get('/latest')
    month_response = Rack::MockRequest.new(described_class).get('/2026-04')

    expect(latest_response.body).to include('No ranking data')
    expect(month_response.status).to eq(200)
    expect(month_response.body).to include('alice/app')
  end

  it 'renders full top 100 pages for each ranking type' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    user_response = Rack::MockRequest.new(described_class).get('/2026-04/locations/krakow/users/active')
    repo_response = Rack::MockRequest.new(described_class).get('/2026-04/repositories/trending')
    latest_user_response = Rack::MockRequest.new(described_class).get('/latest/users/top')
    latest_city_response = Rack::MockRequest.new(described_class).get('/latest/locations/krakow/repositories/top')
    invalid_response = Rack::MockRequest.new(described_class).get('/2026-04/repositories/active')

    expect(user_response.status).to eq(200)
    expect(user_response.body).to include('Top 100 active users')
    expect(repo_response.status).to eq(200)
    expect(repo_response.body).to include('Top 100 trending repositories')
    expect(latest_user_response.status).to eq(200)
    expect(latest_user_response.body).to include('Stars')
    expect(latest_city_response.status).to eq(200)
    expect(latest_city_response.body).to include('Top 100 repositories by stars')
    expect(invalid_response.status).to eq(404)
  end

  it 'renders editions with year pagination' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/editions')

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Editions</title>')
    expect(response.body).to include('>Editions</h1>')
    expect(response.body).to include('April 2026')
    expect(response.body).to include('Top projects')
    expect(response.body).to include('Top users: stars')
    expect(response.body).to include('Top users: activity')
    expect(response.body).to include('href="/2026-04"')
    expect(response.body).to include('href="/editions/2025"')
  end

  it 'renders edition archive year pages and missing years' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    year_response = Rack::MockRequest.new(described_class).get('/editions/2025')
    invalid_response = Rack::MockRequest.new(described_class).get('/editions/2024')

    expect(year_response.status).to eq(200)
    expect(year_response.body).to include('December 2025')
    expect(year_response.body).to include('href="/editions/2026"')
    expect(invalid_response.status).to eq(404)
  end

  it 'renders the about page' do
    response = Rack::MockRequest.new(described_class).get('/about')

    expect(response.status).to eq(200)
    expect(response.body).to include('Mission')
    expect(response.body).to include('Only public data')
    expect(response.body).to include('GitHub')
    expect(response.body).to include('GitLab')
    expect(response.body).to include('Codeberg')
    expect(response.body).to include('Maciej Ciemborowicz')
    expect(response.body).to include('href="/latest/locations/krakow"')
    expect(response.body).not_to include('//locations')
  end

  it 'links about platform cards to source platforms' do
    response = Rack::MockRequest.new(described_class).get('/about')

    expect(response.body).to include('href="https://github.com/"')
    expect(response.body).to include('href="https://gitlab.com/"')
    expect(response.body).to include('href="https://codeberg.org/"')
  end

  it 'uses SVG platform icons instead of text markers' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    ranking_response = Rack::MockRequest.new(described_class).get('/')
    about_response = Rack::MockRequest.new(described_class).get('/about')

    expect(ranking_response.body).to include('src="/icons/github.svg"')
    expect(ranking_response.body).not_to include('>GH</span>')
    expect(about_response.body).to include('src="/icons/gitlab.svg"')
    expect(about_response.body).to include('src="/icons/codeberg.svg"')
    expect(about_response.body).not_to include('Publiczne profile, projekty')
  end

  it 'renders Polish content when requested by accepted language' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    polish_response = request.get('/', 'HTTP_ACCEPT_LANGUAGE' => 'pl-PL,pl;q=0.9')

    expect(polish_response.body).to include('<html lang="pl">')
    expect(polish_response.body).to include('aria-label="Język"')
    expect(polish_response.body).to include('Użytkownicy')
    expect(polish_response.body).to include('Zobacz top 100')
    expect(polish_response.body).to include('href="/?lang=en"')
  end

  it 'renders English content by explicit locale and cookie' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    english_response = request.get('/latest?lang=en')
    cookie_response = request.get('/latest', 'HTTP_COOKIE' => 'locale=en')

    expect(english_response.body).to include('<html lang="en">')
    expect(english_response.body).to include('>Poland</a>')
    expect(english_response.body).to include('>More cities</summary>')
    expect(english_response.body).to include('Top 10 by stars')
    expect(english_response.body).to include('Repositories')
    expect(english_response['Set-Cookie']).to include('locale=en')
    expect(cookie_response.body).to include('<html lang="en">')
  end

  it 'renders links and assets under a configured app base path' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['BASE_URL'] = 'https://rank.example/polish-open-source-rank'
    ENV['APP_BASE_PATH'] = '/polish-open-source-rank'

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.body).to include('rel="canonical" href="https://rank.example/polish-open-source-rank/latest"')
    expect(response.body).to include('href="/polish-open-source-rank/css/application.css?v=20260517-about"')
    expect(response.body).to include('src="/polish-open-source-rank/js/navigation.js?v=20260517-menu3"')
    expect(response.body).to include('src="/polish-open-source-rank/icons/github.svg"')
    expect(response.body).to include('href="/polish-open-source-rank/latest/locations/krakow"')
    expect(response.body).to include('href="/polish-open-source-rank/latest/users/top"')
    expect(response.body).to include('href="/polish-open-source-rank/editions"')
    expect(response.body).to include('href="/polish-open-source-rank/about"')
  end

  it 'serves health checks and 404 pages' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    expect(Rack::MockRequest.new(described_class).get('/healthz').body).to eq('ok')
    expect(Rack::MockRequest.new(described_class).get('/locations/unknown').status).to eq(404)
    expect(Rack::MockRequest.new(described_class).get('/2026-13').status).to eq(404)
  end

  it 'serves internal job progress as noindex JSON' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    response = Rack::MockRequest.new(described_class).get('/internal/jobs')
    body = JSON.parse(response.body)

    expect(response.status).to eq(200)
    expect(response.content_type).to include('application/json')
    expect(response['X-Robots-Tag']).to eq('noindex')
    expect(body.fetch('run')).to include('period_start' => '2026-04-01', 'status' => 'running')
    expect(body.fetch('platforms')).to include(include('platform' => 'github', 'crawled_records_count' => 1))
  end

  def seed_database
    path = empty_database
    store = PolishOpenSourceRank::Infrastructure::SQLiteStore.new(path).migrate!
    older_period = PolishOpenSourceRank::Application::MonthPeriod.parse('2025-12')
    older_run_id = store.create_run(older_period)
    store.upsert_user(user_attributes)
    store.record_user_stats(user_stats(older_period))
    store.upsert_repository(repository_attributes)
    store.record_repository_stats(repository_stats(older_period))
    store.finish_run(older_run_id)

    period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04')
    run_id = store.create_run(period)

    store.upsert_user(user_attributes)
    store.record_user_stats(user_stats(period))
    store.upsert_repository(repository_attributes)
    store.record_repository_stats(repository_stats(period))
    store.finish_run(run_id)
    path
  end

  def seed_running_database
    path = empty_database
    store = PolishOpenSourceRank::Infrastructure::SQLiteStore.new(path).migrate!
    period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04')
    store.create_run(period)

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

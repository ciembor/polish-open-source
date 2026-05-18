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
    expect(latest_user_response.body).to include('/icons/medal-gold.svg')
    expect(latest_city_response.status).to eq(200)
    expect(latest_city_response.body).to include('Top 100 repositories by stars')
    expect(invalid_response.status).to eq(404)
  end

  it 'renders user profile pages from ranking users', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    ranking_response = request.get('/latest/users/top')
    profile_response = request.get('/users/github/alice')
    missing_response = request.get('/users/github/missing')

    expect(ranking_response.body).to include('href="/users/github/alice"')
    expect(profile_response.status).to eq(200)
    expect(profile_response.body).to include('<title>Alice - GitHub profile</title>')
    expect(profile_response.body).to include('rel="canonical" href="https://rank.example/users/github/alice"')
    expect(profile_response.body).to include('src="https://avatars.example/alice.png"')
    expect(profile_response.body).to include('GitHub profile')
    expect(profile_response.body).to include('Best projects')
    expect(profile_response.body).to include('alice/app')
    expect(profile_response.body).to include('/icons/medal-gold.svg')
    expect(profile_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.body).to include('12 345')
    expect(missing_response.status).to eq(404)
  end

  it 'renders repository profile pages and GitHub badges from ranking projects', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    ranking_response = request.get('/latest/repositories/top')
    profile_response = request.get('/repositories/github/alice/app')
    badge_response = request.get('/badges/repositories/github/alice/app.svg')
    missing_response = request.get('/repositories/github/alice/missing')

    expect(ranking_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.status).to eq(200)
    expect(profile_response.body).to include('<title>alice/app - GitHub project</title>')
    expect(profile_response.body).to include('rel="canonical" href="https://rank.example/repositories/github/alice/app"')
    expect(profile_response.body).to include('/icons/medal-gold.svg')
    expect(profile_response.body).to include('GitHub badge')
    expect(profile_response.body).to include('/badges/repositories/github/alice/app.svg')
    expect(badge_response.status).to eq(200)
    expect(badge_response.content_type).to include('image/svg+xml')
    expect(badge_response.body).to include('Polish Elite')
    expect(badge_response.body).to include('1 place')
    expect(badge_response.body).to include('#dc143c')
    expect(missing_response.status).to eq(404)
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
    expect(response.body).to include('href="/polish-open-source-rank/css/application.css?v=20260518-profile2"')
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

  it 'serves internal job progress as a noindex monitor page', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    response = Rack::MockRequest.new(described_class).get('/internal/jobs')

    expect(response.status).to eq(200)
    expect(response.content_type).to include('text/html')
    expect(response['X-Robots-Tag']).to eq('noindex')
    expect(response.body).to include('<title>Job monitor</title>')
    expect(response.body).to include('noindex,nofollow')
    expect(response.body).to include('2026-04-01 to 2026-05-01')
    expect(response.body).to include('CEST')
    expect(response.body).to include('Candidate queue')
    expect(response.body).to include('Total discovered candidates')
    expect(response.body).to include('Stored snapshot')
    expect(response.body).to include('Users stored for the month')
    expect(response.body).to include('Changes since this run started')
    expect(response.body).to include('Repositories stored in this run')
    expect(response.body).to include('Last checked candidate')
    expect(response.body).to include('Last stored repository')
    expect(response.body).to include('API requests per minute')
    expect(response.body).to include('Last monitor events')
    expect(response.body).to include('Last error logs')
    expect(response.body).to include('monitor-axis-label')
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
    seed_extra_ranked_records(store, older_period)
    store.finish_run(older_run_id)

    period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04')
    run_id = store.create_run(period)

    store.upsert_user(user_attributes)
    store.record_user_stats(user_stats(period))
    store.upsert_repository(repository_attributes)
    store.record_repository_stats(repository_stats(period))
    seed_extra_ranked_records(store, period)
    store.finish_run(run_id)
    path
  end

  def seed_extra_ranked_records(store, period)
    [
      [2, 'bob', 'Bob', 7_000],
      [3, 'carol', 'Carol', 3_000]
    ].each do |id, login, name, stars|
      store.upsert_user(user_attributes(id: id, login: login, name: name, avatar_url: nil))
      store.record_user_stats(user_stats(period, user_id: id, login: login, total_stars: stars))
      store.upsert_repository(repository_attributes(id: id + 10, owner_id: id, owner_login: login))
      store.record_repository_stats(
        repository_stats(period, repository_id: id + 10, owner_id: id, owner_login: login, stars: stars)
      )
    end
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

  def user_attributes(id: 1, login: 'alice', name: 'Alice', avatar_url: 'https://avatars.example/alice.png')
    {
      github_id: id,
      login: login,
      name: name,
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: "#{login}@example.com",
      homepage: "https://#{login}.example",
      html_url: "https://github.com/#{login}",
      avatar_url: avatar_url
    }
  end

  def user_stats(period, user_id: 1, login: 'alice', total_stars: 12_345)
    {
      period_start: period.start_date.to_s,
      user_github_id: user_id,
      login: login,
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: total_stars,
      monthly_stars_delta: 5,
      public_activity_count: 8
    }
  end

  def repository_attributes(id: 10, owner_id: 1, owner_login: 'alice')
    {
      github_id: id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      name: 'app',
      full_name: "#{owner_login}/app",
      description: 'Nice Ruby app',
      html_url: "https://github.com/#{owner_login}/app",
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false
    }
  end

  def repository_stats(period, repository_id: 10, owner_id: 1, owner_login: 'alice', stars: 12_345)
    {
      period_start: period.start_date.to_s,
      repository_github_id: repository_id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: stars,
      monthly_stars_delta: 5
    }
  end
end

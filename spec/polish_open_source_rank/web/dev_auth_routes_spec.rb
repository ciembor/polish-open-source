# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Routes::DevAuthRoutes do
  around do |example|
    old_env = ENV.to_h
    old_environment = PolishOpenSourceRank::Web::App.environment
    old_raise_errors = PolishOpenSourceRank::Web::App.raise_errors
    ENV['BASE_URL'] = 'https://rank.example'
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    PolishOpenSourceRank::Web::App.set :environment, :development
    PolishOpenSourceRank::Web::App.set :raise_errors, true
    PolishOpenSourceRank::Web::App.register described_class
    example.run
  ensure
    ENV.replace(old_env)
    PolishOpenSourceRank::Web::App.set :environment, old_environment
    PolishOpenSourceRank::Web::App.set :raise_errors, old_raise_errors
  end

  it 'serves a dev login index page' do
    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev')

    expect(response.status).to eq(200)
    expect(response.body).to include('Dev')
    expect(response.body).to include('Login')
  end

  it 'renders dev login even when the database has no completed periods' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev')

    expect(response.status).to eq(200)
  end

  it 'rejects empty dev login lookups' do
    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev/user')

    expect(response.status).to eq(400)
  end

  it 'redirects dev login lookups for non-empty logins' do
    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev/user?login=alice')

    expect(response.status).to eq(302)
    expect(response['Location']).to include('/auth/dev/alice')
  end

  it 'returns 404 for unknown dev logins' do
    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev/missing')

    expect(response.status).to eq(404)
  end

  it 'logs in as a ranked user without OAuth' do
    response = Rack::MockRequest.new(PolishOpenSourceRank::Web::App).get('/auth/dev/alice')

    expect(response.status).to eq(302)
    expect(response['Location']).to include('/users/github/alice')
  end

  def seed_database
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    period_start = Date.new(2026, 4, 1).to_s
    period_end = Date.new(2026, 4, 30).to_s
    timestamp = Time.utc(2026, 5, 1, 10, 0, 0).iso8601

    database.dataset(:sync_runs).insert(
      period_start: period_start,
      period_end: period_end,
      status: 'finished',
      started_at: timestamp,
      finished_at: timestamp,
      error: nil
    )
    database.dataset(:users).insert(
      platform: 'github',
      github_id: 1,
      login: 'alice',
      name: 'Alice',
      location_raw: 'Krakow, Poland',
      city: 'Krakow',
      country: 'Poland',
      email: nil,
      homepage: nil,
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example/alice.png',
      updated_at: timestamp
    )
    database.dataset(:user_monthly_stats).insert(
      period_start: period_start,
      platform: 'github',
      user_github_id: 1,
      login: 'alice',
      city: 'Krakow',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: 123,
      monthly_stars_delta: 4,
      merged_pull_requests_count: 5,
      updated_at: timestamp
    )
    path
  end

  def empty_database
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database
      .open(path)
      .execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    path
  end
end

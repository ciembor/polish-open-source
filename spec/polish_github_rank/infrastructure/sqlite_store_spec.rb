# frozen_string_literal: true

RSpec.describe PolishGithubRank::Infrastructure::SQLiteStore do
  let(:period) { PolishGithubRank::Application::MonthPeriod.parse('2026-04') }
  let(:path) { File.join(Dir.mktmpdir, 'rank.sqlite3') }
  let(:store) { described_class.new(path).migrate! }

  it 'stores sync progress, snapshots, and scoped rankings' do
    run_id = store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Krakow')
    store.mark_candidate(period, 'alice', 'failed', 'temporary')

    expect(store.pending_candidates(period)).to contain_exactly(include(login: 'alice', github_id: 10))

    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    store.mark_candidate(period, 'alice', 'processed')
    store.finish_run(run_id)

    expect(store.processed_user?(period, 10)).to eq(1)
    expect(store.pending_candidates(period)).to be_empty
    expect(store.latest_period).to eq('2026-04-01')
    expect(store.completed_periods).to contain_exactly(include(period_start: '2026-04-01'))
    expect(store.user_rankings('poland').fetch(:top).first).to include(login: 'alice', total_stars: 30)
    expect(store.user_rankings('krakow').fetch(:active).first).to include(public_activity_count: 9)
    expect(store.repository_rankings('poland').fetch(:trending).first).to include(full_name: 'alice/app',
                                                                                  monthly_stars_delta: 4)
    expect(store.repository_rankings('krakow').fetch(:top).first).to include(full_name: 'alice/app',
                                                                             stargazers_count: 30)
  end

  it 'filters pending candidates by platform' do
    store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'bob', source_query: 'Poland', platform: 'gitlab')

    expect(store.pending_candidates(period, platform: 'gitlab')).to contain_exactly(
      include(login: 'bob', source_id: 20)
    )
  end

  it 'records failed runs' do
    run_id = store.create_run(period)

    expect { store.fail_run(run_id, 'boom') }.not_to raise_error
    expect(store.latest_period).to be_nil
  end

  it 'does not reopen a finished period for partial refreshes' do
    run_id = store.create_run(period)
    store.finish_run(run_id)

    refreshed_run_id = store.create_run(period)

    expect(refreshed_run_id).to be_nil
    expect(store.latest_period).to eq('2026-04-01')
    expect(store.completed_periods).to contain_exactly(include(period_start: '2026-04-01'))
  end

  it 'rolls back ranking pruning failures' do
    broken_catalog = Module.new
    broken_catalog.const_set(:COUNTRY, 'Poland')
    broken_catalog.const_set(:CITIES, [{ slug: 'broken' }].freeze)

    expect { store.prune_rankings(period, catalog: broken_catalog) }.to raise_error(KeyError)
    expect { store.record_candidate(period, github_id: 99, login: 'usable', source_query: 'Poland') }.not_to raise_error
  end

  it 'keeps only records needed for top 100 rankings after a completed snapshot' do
    run_id = store.create_run(period)

    101.times do |index|
      id = index + 1
      login = format('user%03d', id)
      repo_id = id + 1000
      store.upsert_user(user_attributes(id, login, 'Kraków'))
      store.record_user_stats(user_stats(id, login, 'Kraków', total_stars: id, delta: id, activity: id))
      store.upsert_repository(repository_attributes(repo_id, id, login, "#{login}/app", id))
      store.record_repository_stats(repository_stats(repo_id, id, login, 'Kraków', stars: id, delta: id))
    end

    store.prune_rankings(period)
    store.finish_run(run_id)

    expect(store.user_rankings('poland').fetch(:top).length).to eq(100)
    expect(store.repository_rankings('krakow').fetch(:top).length).to eq(100)
    expect(store.user_rankings('poland').fetch(:top).map { |row| row.fetch(:login) }).not_to include('user001')
    pruned_repository_names = store.repository_rankings('poland').fetch(:top).map { |row| row.fetch(:full_name) }
    expect(pruned_repository_names).not_to include('user001/app')
  end

  it 'migrates existing GitHub-only databases to platform-qualified records' do
    old_path = File.join(Dir.mktmpdir, 'old.sqlite3')
    old_database = SQLite3::Database.new(old_path)
    old_database.execute_batch(legacy_schema_sql)
    old_database.execute(
      'INSERT INTO users(github_id, login, html_url, updated_at) VALUES(1, "alice", "https://github.com/alice", "now")'
    )

    migrated_store = described_class.new(old_path).migrate!

    expect(migrated_store.user_rankings('poland', period_start: period.start_date.to_s)).to eq(
      top: [], trending: [], active: []
    )
    database = SQLite3::Database.new(old_path)
    expect(database.get_first_value('SELECT platform FROM users WHERE github_id = 1')).to eq('github')
  end

  def user_attributes(id, login, city)
    {
      github_id: id,
      login: login,
      name: login.capitalize,
      location_raw: "#{city}, Poland",
      city: city,
      country: 'Poland',
      email: "#{login}@example.com",
      homepage: "https://example.com/#{login}",
      html_url: "https://github.com/#{login}",
      avatar_url: "https://avatars.example/#{login}.png"
    }
  end

  def user_stats(id, login, city, total_stars:, delta:, activity:)
    {
      period_start: period.start_date.to_s,
      user_github_id: id,
      login: login,
      city: city,
      country: 'Poland',
      public_repo_count: 1,
      total_stars: total_stars,
      monthly_stars_delta: delta,
      public_activity_count: activity
    }
  end

  def repository_attributes(id, owner_id, owner_login, full_name, stars)
    {
      github_id: id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      name: full_name.split('/').last,
      full_name: full_name,
      description: "Project with #{stars} stars",
      html_url: "https://github.com/#{full_name}",
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false
    }
  end

  def repository_stats(id, owner_id, owner_login, city, stars:, delta:)
    {
      period_start: period.start_date.to_s,
      repository_github_id: id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      owner_city: city,
      owner_country: 'Poland',
      stargazers_count: stars,
      monthly_stars_delta: delta
    }
  end

  def legacy_schema_sql
    <<~SQL
      CREATE TABLE sync_runs (id INTEGER PRIMARY KEY AUTOINCREMENT, period_start TEXT NOT NULL UNIQUE,
        period_end TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, error TEXT);
      CREATE TABLE candidate_users (period_start TEXT NOT NULL, github_id INTEGER NOT NULL, login TEXT NOT NULL,
        source_query TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', error TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL, PRIMARY KEY(period_start, login));
      CREATE TABLE users (github_id INTEGER PRIMARY KEY, login TEXT NOT NULL UNIQUE, name TEXT, location_raw TEXT,
        city TEXT, country TEXT, email TEXT, homepage TEXT, html_url TEXT NOT NULL, avatar_url TEXT, updated_at TEXT NOT NULL);
      CREATE TABLE user_monthly_stats (period_start TEXT NOT NULL, user_github_id INTEGER NOT NULL, login TEXT NOT NULL,
        city TEXT, country TEXT, public_repo_count INTEGER NOT NULL, total_stars INTEGER NOT NULL,
        monthly_stars_delta INTEGER NOT NULL, public_activity_count INTEGER NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY(period_start, user_github_id));
      CREATE TABLE repositories (github_id INTEGER PRIMARY KEY, owner_github_id INTEGER NOT NULL,
        owner_login TEXT NOT NULL, name TEXT NOT NULL, full_name TEXT NOT NULL UNIQUE, description TEXT,
        html_url TEXT NOT NULL, homepage TEXT, language TEXT, fork INTEGER NOT NULL, archived INTEGER NOT NULL,
        updated_at TEXT NOT NULL);
      CREATE TABLE repository_monthly_stats (period_start TEXT NOT NULL, repository_github_id INTEGER NOT NULL,
        owner_github_id INTEGER NOT NULL, owner_login TEXT NOT NULL, owner_city TEXT, owner_country TEXT,
        stargazers_count INTEGER NOT NULL, monthly_stars_delta INTEGER NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY(period_start, repository_github_id));
    SQL
  end
end

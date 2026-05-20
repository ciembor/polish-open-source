# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::SQLiteStore do
  let(:period) { PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04') }
  let(:path) { File.join(Dir.mktmpdir, 'rank.sqlite3') }
  let(:store) { described_class.new(path).migrate! }

  it 'configures SQLite connections for store access patterns' do
    pathname = Pathname(path)
    connection = instance_double(SQLite3::Database)
    allow(connection).to receive(:results_as_hash=)
    allow(connection).to receive(:busy_timeout=)
    allow(connection).to receive(:execute)
    allow(SQLite3::Database).to receive(:new).with(pathname.to_s).and_return(connection)

    described_class.new(pathname).send(:database)

    expect(connection).to have_received(:results_as_hash=).with(true)
    expect(connection).to have_received(:busy_timeout=).with(120_000)
    expect(connection).to have_received(:execute).with('PRAGMA foreign_keys = ON')
  end

  it 'stores sync progress, snapshots, and scoped rankings' do
    run_id = store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Krakow')
    store.mark_candidate(period, 'alice', 'failed', 'temporary')

    expect(store.pending_candidates(period)).to be_empty

    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    store.mark_candidate(period, 'alice', 'processed')
    store.finish_run(run_id)

    expect(store.processed_user?(period, 10)).to eq(1)
    expect(store.pending_candidates(period)).to be_empty
    expect(store.retryable_candidates?(period)).to be(false)
    expect(store.latest_period).to eq('2026-04-01')
    expect(store.completed_periods).to contain_exactly(include(period_start: '2026-04-01'))
    expect(store.user_rankings('poland').fetch(:top).first).to include(login: 'alice', total_stars: 30)
    expect(store.user_rankings('krakow').fetch(:active).first).to include(public_activity_count: 9)
    expect(store.repository_rankings('poland').fetch(:trending).first).to include(full_name: 'alice/app',
                                                                                  monthly_stars_delta: 4)
    expect(store.repository_rankings('krakow').fetch(:top).first).to include(full_name: 'alice/app',
                                                                             stargazers_count: 30)
  end

  it 'reports recorded periods and processed users through legacy and platform-aware calls' do
    store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))

    expect(store.processed_user?(period, 10)).to eq(1)
    expect(store.processed_user?(period, 'github', 10)).to eq(1)
    expect(store.recorded_period?('2026-04-01')).to be(true)
    expect(store.recorded_period?('2026-05-01')).to be(false)
    expect(store.retryable_candidates?(period)).to be(false)
  end

  it 'does not treat user stats as complete when repository stats are missing' do
    store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))

    expect(store.processed_user?(period, 10)).to be_nil

    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))

    expect(store.processed_user?(period, 10)).to eq(1)
  end

  it 'keeps city rankings scoped to the requested city' do
    seed_city_scope_rankings

    expect(store.user_rankings('poland').fetch(:top).map { |row| row.fetch(:login) }).to eq(%w[bob alice])
    expect(store.user_rankings('krakow').fetch(:active).map { |row| row.fetch(:login) }).to eq(['alice'])
    expect(store.repository_rankings('poland').fetch(:top).map { |row| row.fetch(:full_name) }).to eq(
      ['bob/app', 'alice/app']
    )
    expect(store.repository_rankings('krakow').fetch(:top).map { |row| row.fetch(:full_name) }).to eq(['alice/app'])
  end

  it 'returns monthly editions with top records once stats exist' do
    run_id = store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    3.times do |index|
      id = index + 20
      login = "extra#{index}"
      store.upsert_user(user_attributes(id, login, 'Kraków'))
      store.record_user_stats(user_stats(id, login, 'Kraków', total_stars: id, delta: id, activity: id))
      store.upsert_repository(repository_attributes(id + 100, id, login, "#{login}/app", id))
      store.record_repository_stats(repository_stats(id + 100, id, login, 'Kraków', stars: id, delta: id))
    end

    expect(store.edition_years).to contain_exactly(include(year: '2026'))
    expect(store.monthly_editions(2026).first).to include(
      period_start: '2026-04-01',
      repositories: [
        include(full_name: 'alice/app'),
        include(full_name: 'extra2/app'),
        include(full_name: 'extra1/app')
      ],
      users_by_stars: [include(login: 'alice'), include(login: 'extra2'), include(login: 'extra1')],
      users_by_activity: [include(login: 'extra2'), include(login: 'extra1'), include(login: 'extra0')]
    )
    store.finish_run(run_id)
  end

  it 'uses the newest period with stored rankings as the latest public period' do
    ranked_run_id = store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.finish_run(ranked_run_id)

    empty_period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-05')
    store.finish_run(store.create_run(empty_period))

    expect(store.latest_period).to eq('2026-04-01')
  end

  it 'uses a running period with stored rankings as the latest public period' do
    store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))

    expect(store.latest_period).to eq('2026-04-01')
  end

  it 'classifies user badges as current elite, alumni, or contender' do
    older_period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-03')
    store.create_run(older_period)
    store.upsert_user(user_attributes(11, 'alumni', 'Kraków'))
    store.record_user_stats(
      user_stats(11, 'alumni', 'Kraków', total_stars: 1_000, delta: 0, activity: 1)
        .merge(period_start: older_period.start_date.to_s)
    )
    store.create_run(period)

    12.times do |index|
      id = index + 1
      login = id == 11 ? 'alumni' : "user#{id}"
      login = 'contender' if id == 12
      store.upsert_user(user_attributes(id, login, 'Kraków'))
      store.record_user_stats(user_stats(id, login, 'Kraków', total_stars: 100 - id, delta: 0, activity: 1))
    end

    expect(store.user_profile('github', 'user1').fetch(:elite_badge)).to include(value: '1st', status: 'ranked')
    expect(store.user_profile('github', 'alumni').fetch(:elite_badge)).to include(value: 'alumni', status: 'alumni')
    expect(store.user_profile('github', 'contender').fetch(:elite_badge)).to include(
      value: 'contender',
      status: 'contender'
    )
  end

  # rubocop:disable RSpec/ExampleLength
  it 'stores Discord links, one-time invites, and ranking role keys' do
    store.upsert_user(user_attributes(1, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(1, 'alice', 'Kraków', total_stars: 100, delta: 0, activity: 1))
    store.upsert_user(user_attributes(2, 'bob', 'Kraków'))
    store.record_user_stats(user_stats(2, 'bob', 'Kraków', total_stars: 90, delta: 0, activity: 1))
    store.upsert_user(user_attributes(3, 'carol', 'Kraków'))
    store.record_user_stats(user_stats(3, 'carol', 'Kraków', total_stars: 80, delta: 0, activity: 1))
    (4..11).each do |id|
      login = "user#{id}"
      store.upsert_user(user_attributes(id, login, 'Kraków'))
      store.record_user_stats(user_stats(id, login, 'Kraków', total_stars: 70 - id, delta: 0, activity: 1))
    end

    store.upsert_discord_connection(
      platform: 'github',
      user_github_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice D'
    )
    store.record_discord_invite(platform: 'github', user_github_id: 1, code: 'abc', url: 'https://discord.gg/abc')
    store.record_discord_invite(platform: 'github', user_github_id: 1, code: 'def', url: 'https://discord.gg/def')

    expect(store.discord_connection('github', 1)).to include(discord_user_id: 'discord-1',
                                                             discord_username: 'Alice D')
    expect(store.discord_invite('github', 1)).to include(code: 'def', url: 'https://discord.gg/def')
    expect(store.discord_invite_profile('def')).to include(platform: 'github', github_id: 1, login: 'alice')
    expect(store.discord_access('github', 1)).to include(
      country_rank: 1,
      city: 'Kraków',
      city_slug: 'krakow',
      city_rank: 1,
      role_keys: contain_exactly(
        'DISCORD_ROLE_TOP_10_PL',
        'DISCORD_ROLE_TOP_100_PL',
        'DISCORD_ROLE_TOP_100_CITY_KRAKOW',
        'DISCORD_ROLE_BADGE_TOP_1'
      )
    )
    expect(store.discord_access('github', 2).fetch(:badge_role_key)).to eq('DISCORD_ROLE_BADGE_TOP_2')
    expect(store.discord_access('github', 3).fetch(:badge_role_key)).to eq('DISCORD_ROLE_BADGE_TOP_3')
    expect(store.discord_access('github', 4).fetch(:badge_role_key)).to be_nil
    expect(store.discord_access('github', 11).fetch(:badge_role_key)).to be_nil
  end
  # rubocop:enable RSpec/ExampleLength

  it 'only gives repository badges a visible rank inside the current top 100' do
    store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))

    101.times do |index|
      id = index + 1
      full_name = id == 101 ? 'alice/outside' : "alice/project#{id}"
      store.upsert_repository(repository_attributes(id, 10, 'alice', full_name, 200 - id))
      store.record_repository_stats(repository_stats(id, 10, 'alice', 'Kraków', stars: 200 - id, delta: 0))
    end

    expect(store.repository_profile('github', 'alice', 'project1').fetch(:polish_repo_badge)).to include(
      label: 'Polish Repo',
      value: '1st',
      status: 'ranked'
    )
    expect(store.repository_profile('github', 'alice', 'outside').fetch(:polish_repo_badge)).to include(
      label: 'Polish Repo',
      value: nil,
      status: 'outside_top_100'
    )
  end

  it 'formats ranked badge positions with English ordinal suffixes' do
    rank = PolishOpenSourceRank::Contexts::Publication::Domain::Rank

    expect([1, 2, 3, 4, 11, 12, 13, 21].map { |position| rank.place(position) }).to eq(
      %w[1st 2nd 3rd 4th 11th 12th 13th 21st]
    )
  end

  it 'binds monthly edition year as a positional SQL parameter' do
    unwired_store = described_class.allocate
    allow(unwired_store).to receive(:fetch_all).and_return([])

    expect(unwired_store.monthly_editions(2026)).to eq([])
    expect(unwired_store).to have_received(:fetch_all).with(include('substr(period_start, 1, 4)'), ['2026'])
  end

  it 'binds recorded period checks as positional SQL parameters' do
    unwired_store = described_class.allocate
    allow(unwired_store).to receive(:fetch_value).and_return(1)

    expect(unwired_store.recorded_period?('2026-04-01')).to be(true)
    expect(unwired_store).to have_received(:fetch_value).with(include('period_start = ?'), ['2026-04-01'])
  end

  it 'reports per-platform job progress for the current run' do
    seed_progress_run
    set_current_run_times(started_at: '2026-04-01T10:00:00Z', finished_at: nil)

    expect(store.job_progress(now: Time.utc(2026, 4, 1, 10, 1, 1))).to eq(expected_running_progress)
  end

  it 'separates edition totals from records touched during the current run' do
    seed_progress_run
    database.execute(
      'UPDATE user_monthly_stats SET updated_at = ? WHERE platform = ? AND user_github_id = ?',
      ['2026-04-01T09:59:59Z', 'github', 10]
    )
    set_current_run_times(started_at: '2026-04-01T10:00:00Z', finished_at: nil)

    progress = store.job_progress(now: Time.utc(2026, 4, 1, 10, 1, 1)).fetch(:platforms).first

    expect(progress).to include(
      accepted_users_count: 1,
      current_run_accepted_users_count: 0
    )
  end

  it 'reports processed user progress from user stats timestamps instead of discovery timestamps' do
    seed_progress_run
    set_current_run_times(started_at: '2026-04-01T10:00:00Z', finished_at: nil)
    database.execute(
      'UPDATE candidate_users SET updated_at = ? WHERE platform = ? AND login = ?',
      ['2026-04-01T10:05:00Z', 'github', 'alice']
    )

    progress = store.job_progress(now: Time.utc(2026, 4, 1, 10, 6, 0))

    expect(progress.fetch(:platforms).first.fetch(:last_checked_user)).to eq(
      login: 'alice',
      status: 'processed',
      checked_at: '2026-04-01T10:00:25Z'
    )
  end

  it 'records API requests for job monitoring' do
    seed_progress_run
    set_current_run_times(started_at: '2026-04-01T10:00:00Z', finished_at: nil)

    record_github_api_request(status: 200, second: 40)
    record_github_api_request(status: 403, second: 50)
    progress = store.job_progress(now: Time.utc(2026, 4, 1, 10, 1, 1))

    expect(progress.fetch(:platforms).first.fetch(:last_api_request)).to eq(
      path: '/search/users',
      status: 403,
      recorded_at: '2026-04-01T10:00:50Z'
    )
    expect(progress.fetch(:request_points)).to contain_exactly(
      platform: 'github',
      minute: '2026-04-01T10:00:00Z',
      requests_count: 2,
      error_count: 1
    )
    expect(progress.fetch(:recent_errors)).to contain_exactly(
      platform: 'github',
      source: 'api',
      subject: '/search/users',
      detail: 'HTTP 403',
      recorded_at: '2026-04-01T10:00:50Z'
    )
  end

  it 'reports an empty job progress snapshot when no run exists' do
    now = Time.utc(2026, 4, 1, 10, 1, 1)

    expect(store.job_progress(now: now)).to eq(
      generated_at: '2026-04-01T10:01:01Z',
      run: nil,
      platforms: []
    )
  end

  it 'generates job progress timestamps in UTC by default' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 1, 1, '+02:00') }

    expect(store.job_progress.fetch(:generated_at)).to eq('2026-04-01T10:01:01Z')
  end

  it 'uses the finished run timestamp for completed progress duration' do
    seed_progress_run
    store.finish_run(1)
    set_current_run_times(
      started_at: '2026-04-01T10:00:00Z',
      finished_at: '2026-04-01T10:02:03Z'
    )

    progress = store.job_progress(now: Time.utc(2026, 4, 1, 10, 10, 0))

    expect(progress.fetch(:run)).to include(
      status: 'finished',
      started_at: '2026-04-01T10:00:00Z',
      finished_at: '2026-04-01T10:02:03Z'
    )
    expect(progress.fetch(:platforms).map { |platform| platform.fetch(:run_duration_seconds) }).to eq([123, 123, 123])
  end

  it 'persists complete user records with platform-qualified keys' do
    seed_complete_gitlab_records
    expect(fetch_row('SELECT * FROM users WHERE platform = ? AND github_id = ?', ['gitlab', 10])).to include(
      platform: 'gitlab',
      github_id: 10,
      login: 'alice',
      name: 'Alice',
      location_raw: 'Kraków, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: 'alice@example.com',
      homepage: 'https://example.com/alice',
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example/alice.png'
    )
  end

  it 'persists complete repository records with platform-qualified keys' do
    seed_complete_gitlab_records
    expect(fetch_row(<<~SQL, ['gitlab', 100])).to include(
      SELECT * FROM repositories WHERE platform = ? AND github_id = ?
    SQL
      platform: 'gitlab',
      github_id: 100,
      owner_github_id: 10,
      owner_login: 'alice',
      name: 'app',
      full_name: 'alice/app',
      description: 'Project with 30 stars',
      html_url: 'https://github.com/alice/app',
      homepage: 'https://app.example',
      language: 'Ruby',
      fork: 1,
      archived: 1
    )
  end

  it 'persists complete user stats with platform-qualified keys' do
    seed_complete_gitlab_records
    expect(fetch_row(<<~SQL, ['2026-04-01', 'gitlab', 10])).to include(
      SELECT * FROM user_monthly_stats WHERE period_start = ? AND platform = ? AND user_github_id = ?
    SQL
      period_start: '2026-04-01',
      platform: 'gitlab',
      user_github_id: 10,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: 30,
      monthly_stars_delta: 4,
      public_activity_count: 9
    )
  end

  it 'persists complete repository stats with platform-qualified keys' do
    seed_complete_gitlab_records
    expect(fetch_row(<<~SQL, ['2026-04-01', 'gitlab', 100])).to include(
      SELECT * FROM repository_monthly_stats WHERE period_start = ? AND platform = ? AND repository_github_id = ?
    SQL
      period_start: '2026-04-01',
      platform: 'gitlab',
      repository_github_id: 100,
      owner_github_id: 10,
      owner_login: 'alice',
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: 30,
      monthly_stars_delta: 4
    )
  end

  it 'records repository stats timestamps in UTC' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))

    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))

    expect(fetch_row('SELECT updated_at FROM repository_monthly_stats WHERE repository_github_id = ?', [100]))
      .to include(updated_at: '2026-04-01T10:00:00Z')
  end

  it 'keeps repository star observations for future monthly deltas' do
    previous_period = PolishOpenSourceRank::Application::MonthPeriod.parse('2026-03')
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))

    store.record_repository_stats(
      repository_stats(100, 10, 'alice', 'Kraków', stars: 27, delta: 0).merge(
        period_start: previous_period.start_date.to_s
      )
    )
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 3))

    expect(store.previous_repository_stargazers_count(period, 'github', 100)).to eq(27)
    expect(fetch_row(<<~SQL, ['2026-04-01', 'github', 100])).to include(stargazers_count: 30)
      SELECT stargazers_count
      FROM repository_star_observations
      WHERE period_start = ? AND platform = ? AND repository_github_id = ?
    SQL
  end

  it 'keeps optional persisted fields nil when source data omits them' do
    store.create_run(period)
    store.upsert_user(minimal_user_attributes)
    store.record_user_stats(minimal_user_stats)
    store.upsert_repository(minimal_repository_attributes)
    store.record_repository_stats(minimal_repository_stats)

    expect(fetch_row('SELECT * FROM users WHERE platform = ? AND github_id = ?', ['github', 50])).to include(
      name: nil,
      location_raw: nil,
      city: nil,
      country: nil,
      email: nil,
      homepage: nil,
      avatar_url: nil
    )
    expect(fetch_row('SELECT * FROM repositories WHERE platform = ? AND github_id = ?', ['github', 500])).to include(
      description: nil,
      homepage: nil,
      language: nil,
      fork: 0,
      archived: 0
    )
  end

  it 'excludes zero monthly deltas from trending rankings' do
    run_id = store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    store.upsert_user(user_attributes(20, 'bob', 'Kraków'))
    store.record_user_stats(user_stats(20, 'bob', 'Kraków', total_stars: 99, delta: 0, activity: 20))
    store.upsert_repository(repository_attributes(200, 20, 'bob', 'bob/app', 99))
    store.record_repository_stats(repository_stats(200, 20, 'bob', 'Kraków', stars: 99, delta: 0))
    store.finish_run(run_id)

    expect(store.user_rankings('poland').fetch(:top).map { |row| row.fetch(:login) }).to eq(%w[bob alice])
    expect(store.user_rankings('poland').fetch(:trending).map { |row| row.fetch(:login) }).to eq(['alice'])
    expect(store.repository_rankings('poland').fetch(:top).map { |row| row.fetch(:full_name) }).to eq(
      ['bob/app', 'alice/app']
    )
    expect(store.repository_rankings('poland').fetch(:trending).map { |row| row.fetch(:full_name) }).to eq(
      ['alice/app']
    )
  end

  it 'filters pending candidates by platform' do
    store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'bob', source_query: 'Poland', platform: 'gitlab')

    expect(store.pending_candidates(period)).to contain_exactly(
      include(login: 'alice', source_id: 10),
      include(login: 'bob', source_id: 20)
    )
    expect(store.pending_candidates(period, platform: 'gitlab')).to contain_exactly(
      include(login: 'bob', source_id: 20)
    )
  end

  it 'returns pending candidates in batches of 100 by default' do
    store.create_run(period)
    101.times do |index|
      store.record_candidate(period, github_id: index, login: format('user%03d', index), source_query: 'Poland')
    end

    expect(store.pending_candidates(period).size).to eq(100)
  end

  it 'records candidate timestamps in UTC' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    store.create_run(period)

    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')

    expect(fetch_candidate('alice')).to include(updated_at: '2026-04-01T10:00:00Z')
  end

  it 'keeps checked candidate timestamps stable during repeated discovery' do
    store.create_run(period)
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.mark_candidate(period, 'alice', 'processed')

    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 5, 0, '+02:00') }
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Krakow')

    expect(fetch_candidate('alice')).to include(status: 'processed', updated_at: '2026-04-01T10:00:00Z')
    expect(fetch_row('SELECT source_query FROM candidate_users WHERE login = ?', ['alice'])).to include(
      source_query: 'Poland, Krakow'
    )
  end

  it 'marks candidates with platform-aware and legacy GitHub arguments' do
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }
    store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'cora', source_query: 'Poland', platform: 'codeberg')

    store.mark_candidate(period, 'alice', 'failed', 'legacy error')
    store.mark_candidate(period, 'codeberg', 'cora', 'failed', 'source error')

    expect(fetch_candidate('alice')).to include(platform: 'github', status: 'failed', error: 'legacy error',
                                                updated_at: '2026-04-01T10:00:00Z')
    expect(fetch_candidate('cora', platform: 'codeberg')).to include(platform: 'codeberg', status: 'failed',
                                                                     error: 'source error')
  end

  it 'records failed runs' do
    run_id = store.create_run(period)

    expect { store.fail_run(run_id, 'boom') }.not_to raise_error
    expect(store.latest_period).to be_nil
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE id = ?', [run_id])).to include(
      status: 'failed',
      error: 'boom'
    )
  end

  it 'creates parent directories and records the schema version' do
    nested_path = File.join(Dir.mktmpdir, 'nested', 'rank.sqlite3')

    nested_store = described_class.new(nested_path).migrate!

    nested_database = SQLite3::Database.new(nested_path)
    expect(nested_database.get_first_value('PRAGMA user_version')).to eq(described_class::SCHEMA_VERSION)
    expect(nested_store.send(:database).get_first_value('PRAGMA foreign_keys')).to eq(1)
    expect(nested_store.latest_period).to be_nil
  end

  it 'does not reopen a finished period for partial refreshes' do
    run_id = store.create_run(period)
    store.finish_run(run_id)

    refreshed_run_id = store.create_run(period)

    expect(refreshed_run_id).to be_nil
    expect(store.latest_period).to be_nil
    expect(store.completed_periods).to contain_exactly(include(period_start: '2026-04-01'))
  end

  it 'reopens selected platform candidates for an explicit refresh' do
    run_id = store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'bob', source_query: 'Poland', platform: 'gitlab')
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(
      user_stats(10, 'alice', 'Kraków', total_stars: 0, delta: 0, activity: 0).merge(public_repo_count: 0)
    )
    store.mark_candidate(period, 'github', 'alice', 'processed')
    store.mark_candidate(period, 'gitlab', 'bob', 'processed')
    store.finish_run(run_id)

    refreshed_run_id = store.create_run(period, refresh_platforms: ['gitlab'])

    expect(refreshed_run_id).to eq(run_id)
    expect(store.pending_candidates(period, platform: 'gitlab')).to contain_exactly(include(login: 'bob'))
    expect(store.pending_candidates(period, platform: 'github')).to be_empty
  end

  it 'reopens a finished period when retryable candidates remain' do
    run_id = store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.mark_candidate(period, 'alice', 'failed', 'temporary')
    store.finish_run(run_id)

    expect(store.retryable_candidates?(period)).to be(true)

    refreshed_run_id = store.create_run(period)

    expect(refreshed_run_id).to eq(run_id)
    expect(store.pending_candidates(period)).to contain_exactly(include(login: 'alice', source_id: 10))
    expect(fetch_row('SELECT status, error FROM candidate_users WHERE login = ?', ['alice'])).to include(
      status: 'pending',
      error: nil
    )
  end

  it 'checks retryable candidates within selected platforms' do
    store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'bob', source_query: 'Poland', platform: 'gitlab')
    store.upsert_user(user_attributes(20, 'bob', 'Kraków').merge(platform: 'gitlab'))
    store.record_user_stats(
      user_stats(20, 'bob', 'Kraków', total_stars: 0, delta: 0, activity: 0).merge(
        platform: 'gitlab',
        public_repo_count: 0
      )
    )
    store.mark_candidate(period, 'gitlab', 'bob', 'processed')

    expect(store.retryable_candidates?(period, platforms: ['github'])).to be(true)
    expect(store.retryable_candidates?(period, platforms: ['gitlab'])).to be(false)
  end

  it 'reopens processed candidates whose repository stats were not fully recorded' do
    run_id = store.create_run(period)
    store.record_candidate(period, platform: 'gitlab', source_id: 10, login: 'alice', source_query: 'Poland')
    store.upsert_user(user_attributes(10, 'alice', 'Kraków').merge(platform: 'gitlab'))
    store.record_user_stats(
      user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9).merge(platform: 'gitlab')
    )
    store.mark_candidate(period, 'gitlab', 'alice', 'processed')
    store.finish_run(run_id)

    expect(store.processed_user?(period, 'gitlab', 10)).to be_nil
    expect(store.retryable_candidates?(period)).to be(true)

    refreshed_run_id = store.create_run(period)

    expect(refreshed_run_id).to eq(run_id)
    expect(store.pending_candidates(period, platform: 'gitlab')).to contain_exactly(
      include(login: 'alice', source_id: 10)
    )
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

  def minimal_user_attributes
    {
      github_id: 50,
      login: 'optional',
      html_url: 'https://github.com/optional'
    }
  end

  def seed_city_scope_rankings
    run_id = store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    store.upsert_user(user_attributes(20, 'bob', 'Wrocław'))
    store.record_user_stats(user_stats(20, 'bob', 'Wrocław', total_stars: 99, delta: 9, activity: 19))
    store.upsert_repository(repository_attributes(200, 20, 'bob', 'bob/app', 99))
    store.record_repository_stats(repository_stats(200, 20, 'bob', 'Wrocław', stars: 99, delta: 9))
    store.finish_run(run_id)
  end

  def minimal_user_stats
    {
      period_start: period.start_date.to_s,
      user_github_id: 50,
      login: 'optional',
      public_repo_count: 0,
      total_stars: 0,
      monthly_stars_delta: 0,
      public_activity_count: 0
    }
  end

  def minimal_repository_attributes
    {
      github_id: 500,
      owner_github_id: 50,
      owner_login: 'optional',
      name: 'tool',
      full_name: 'optional/tool',
      html_url: 'https://github.com/optional/tool',
      fork: false,
      archived: false
    }
  end

  def minimal_repository_stats
    {
      period_start: period.start_date.to_s,
      repository_github_id: 500,
      owner_github_id: 50,
      owner_login: 'optional',
      stargazers_count: 0,
      monthly_stars_delta: 0
    }
  end

  def seed_progress_run
    store.create_run(period)
    store.record_candidate(period, github_id: 10, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, source_id: 20, login: 'bob', source_query: 'Poland', platform: 'gitlab')
    store.mark_candidate(period, 'github', 'alice', 'processed')
    store.mark_candidate(period, 'gitlab', 'bob', 'missing')
    store.upsert_user(user_attributes(10, 'alice', 'Kraków'))
    store.record_user_stats(user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9))
    store.upsert_repository(repository_attributes(100, 10, 'alice', 'alice/app', 30))
    store.record_repository_stats(repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4))
    seed_progress_timestamps
  end

  def seed_progress_timestamps
    database.execute(
      'UPDATE candidate_users SET updated_at = ? WHERE platform = ? AND login = ?',
      ['2026-04-01T10:00:20Z', 'github', 'alice']
    )
    database.execute(
      'UPDATE user_monthly_stats SET updated_at = ? WHERE platform = ? AND user_github_id = ?',
      ['2026-04-01T10:00:25Z', 'github', 10]
    )
    database.execute(
      'UPDATE candidate_users SET updated_at = ? WHERE platform = ? AND login = ?',
      ['2026-04-01T10:00:10Z', 'gitlab', 'bob']
    )
    database.execute(
      'UPDATE repository_monthly_stats SET updated_at = ? WHERE platform = ? AND repository_github_id = ?',
      ['2026-04-01T10:00:30Z', 'github', 100]
    )
  end

  def seed_complete_gitlab_records
    store.create_run(period)
    store.upsert_user(user_attributes(10, 'alice', 'Kraków').merge(platform: 'gitlab'))
    store.record_user_stats(
      user_stats(10, 'alice', 'Kraków', total_stars: 30, delta: 4, activity: 9).merge(platform: 'gitlab')
    )
    store.upsert_repository(gitlab_repository_record)
    store.record_repository_stats(
      repository_stats(100, 10, 'alice', 'Kraków', stars: 30, delta: 4).merge(platform: 'gitlab')
    )
  end

  def gitlab_repository_record
    repository_attributes(100, 10, 'alice', 'alice/app', 30).merge(
      platform: 'gitlab',
      homepage: 'https://app.example',
      fork: true,
      archived: true
    )
  end

  def expected_running_progress
    {
      generated_at: '2026-04-01T10:01:01Z',
      run: expected_running_progress_run,
      platforms: expected_running_progress_platforms,
      progress_points: [
        {
          platform: 'github',
          minute: '2026-04-01T10:00:00Z',
          checked_users_count: 1,
          checked_repositories_count: 1
        }
      ],
      request_points: [],
      recent_events: [
        {
          platform: 'github',
          source: 'repository',
          subject: 'alice/app',
          detail: 'stored',
          recorded_at: '2026-04-01T10:00:30Z'
        },
        {
          platform: 'github',
          source: 'candidate',
          subject: 'alice',
          detail: 'processed',
          recorded_at: '2026-04-01T10:00:20Z'
        },
        {
          platform: 'gitlab',
          source: 'candidate',
          subject: 'bob',
          detail: 'missing',
          recorded_at: '2026-04-01T10:00:10Z'
        }
      ],
      recent_errors: []
    }
  end

  def expected_running_progress_run
    {
      period_start: '2026-04-01',
      period_end: '2026-05-01',
      status: 'running',
      started_at: '2026-04-01T10:00:00Z',
      finished_at: nil,
      error: nil
    }
  end

  def expected_running_progress_platforms
    [
      expected_github_progress,
      expected_gitlab_progress,
      expected_codeberg_progress
    ]
  end

  def expected_github_progress
    {
      platform: 'github',
      run_duration_seconds: 61,
      crawled_records_count: 2,
      total_candidates_count: 1,
      checked_candidates_count: 1,
      checked_users_count: 1,
      accepted_users_count: 1,
      checked_repositories_count: 1,
      repository_owners_count: 1,
      zero_repository_users_count: 0,
      pending_candidates_count: 0,
      rejected_candidates_count: 0,
      missing_candidates_count: 0,
      failed_candidates_count: 0,
      current_run_checked_candidates_count: 1,
      current_run_accepted_users_count: 1,
      current_run_repository_owners_count: 1,
      current_run_repositories_count: 1,
      last_checked_user: { login: 'alice', status: 'processed', checked_at: '2026-04-01T10:00:25Z' },
      last_checked_repository: { full_name: 'alice/app', owner_login: 'alice', checked_at: '2026-04-01T10:00:30Z' },
      last_api_request: nil
    }
  end

  def expected_gitlab_progress
    {
      platform: 'gitlab',
      run_duration_seconds: 61,
      crawled_records_count: 1,
      total_candidates_count: 1,
      checked_candidates_count: 1,
      checked_users_count: 1,
      accepted_users_count: 0,
      checked_repositories_count: 0,
      repository_owners_count: 0,
      zero_repository_users_count: 0,
      pending_candidates_count: 0,
      rejected_candidates_count: 0,
      missing_candidates_count: 1,
      failed_candidates_count: 0,
      current_run_checked_candidates_count: 1,
      current_run_accepted_users_count: 0,
      current_run_repository_owners_count: 0,
      current_run_repositories_count: 0,
      last_checked_user: { login: 'bob', status: 'missing', checked_at: '2026-04-01T10:00:10Z' },
      last_checked_repository: nil,
      last_api_request: nil
    }
  end

  def expected_codeberg_progress
    {
      platform: 'codeberg',
      run_duration_seconds: 61,
      crawled_records_count: 0,
      total_candidates_count: 0,
      checked_candidates_count: 0,
      checked_users_count: 0,
      accepted_users_count: 0,
      checked_repositories_count: 0,
      repository_owners_count: 0,
      zero_repository_users_count: 0,
      pending_candidates_count: 0,
      rejected_candidates_count: 0,
      missing_candidates_count: 0,
      failed_candidates_count: 0,
      current_run_checked_candidates_count: 0,
      current_run_accepted_users_count: 0,
      current_run_repository_owners_count: 0,
      current_run_repositories_count: 0,
      last_checked_user: nil,
      last_checked_repository: nil,
      last_api_request: nil
    }
  end

  def set_current_run_times(started_at:, finished_at:)
    status = finished_at ? 'finished' : 'running'
    database.execute(
      'UPDATE sync_runs SET started_at = ?, finished_at = ?, status = ? WHERE period_start = ?',
      [started_at, finished_at, status, period.start_date.to_s]
    )
  end

  def record_github_api_request(status:, second:)
    store.record_api_request(
      platform: 'github',
      path: '/search/users',
      status: status,
      recorded_at: Time.utc(2026, 4, 1, 10, 0, second)
    )
  end

  def fetch_row(sql, params = [])
    row = database.execute(sql, params).first
    row.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value unless key.is_a?(Integer)
    end
  end

  def fetch_candidate(login, platform: 'github')
    fetch_row(
      'SELECT platform, login, status, error, updated_at FROM candidate_users WHERE platform = ? AND login = ?',
      [platform, login]
    )
  end

  def database
    @database ||= SQLite3::Database.new(path).tap do |connection|
      connection.results_as_hash = true
    end
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

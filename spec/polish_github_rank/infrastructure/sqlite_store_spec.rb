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
    expect(store.user_rankings('poland').fetch(:top).first).to include(login: 'alice', total_stars: 30)
    expect(store.user_rankings('krakow').fetch(:active).first).to include(public_activity_count: 9)
    expect(store.repository_rankings('poland').fetch(:trending).first).to include(full_name: 'alice/app',
                                                                                  monthly_stars_delta: 4)
    expect(store.repository_rankings('krakow').fetch(:top).first).to include(full_name: 'alice/app',
                                                                             stargazers_count: 30)
  end

  it 'records failed runs' do
    run_id = store.create_run(period)

    expect { store.fail_run(run_id, 'boom') }.not_to raise_error
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
end

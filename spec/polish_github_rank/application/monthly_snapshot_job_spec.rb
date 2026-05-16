# frozen_string_literal: true

class FakeJobGitHub
  attr_accessor :activities, :candidates, :deltas, :fail_logins, :missing_logins, :profiles, :repositories

  def initialize
    @activities = {}
    @candidates = {}
    @deltas = {}
    @fail_logins = []
    @missing_logins = []
    @profiles = {}
    @repositories = {}
  end

  def search_users_by_location(term)
    candidates.fetch(term, [])
  end

  def user(login)
    raise 'boom' if fail_logins.include?(login)
    raise missing_error if missing_logins.include?(login)

    profiles.fetch(login)
  end

  def repositories_for(login)
    repositories.fetch(login, [])
  end

  def repository_stars_delta(full_name, _period)
    deltas.fetch(full_name, 0)
  end

  def public_activity_count(login, _period)
    activities.fetch(login, 0)
  end

  private

  def missing_error
    PolishGithubRank::Infrastructure::GitHubClient::NotFound.new('missing', status: 404, body: '{}')
  end
end

RSpec.describe PolishGithubRank::Application::MonthlySnapshotJob do
  let(:period) { PolishGithubRank::Application::MonthPeriod.parse('2026-04') }
  let(:store) { PolishGithubRank::Infrastructure::SQLiteStore.new(File.join(Dir.mktmpdir, 'job.sqlite3')).migrate! }
  let(:catalog) { double('catalog', search_terms: ['Poland']) }
  let(:github) { FakeJobGitHub.new }
  let(:job) { described_class.new(store: store, github: github, catalog: catalog, logger: StringIO.new) }

  it 'discovers candidates, rejects non-Polish profiles, and stores Polish snapshots' do
    github.candidates = { 'Poland' => [{ 'id' => 1, 'login' => 'alice' }, { 'id' => 2, 'login' => 'bob' }] }
    github.profiles = {
      'alice' => profile(1, 'alice', 'Krakow, Poland', blog: ''),
      'bob' => profile(2, 'bob', 'Berlin, Germany')
    }
    github.repositories = { 'alice' => [repository(10, 'alice/app', 12), repository(11, 'alice/lib', 5, homepage: '')] }
    github.deltas = { 'alice/app' => 3, 'alice/lib' => 1 }
    github.activities = { 'alice' => 7 }

    job.call(period)

    expect(store.user_rankings('poland').fetch(:trending).first).to include(login: 'alice', monthly_stars_delta: 4)
    expect(store.user_rankings('krakow').fetch(:active).first).to include(public_activity_count: 7)
    expect(store.repository_rankings('poland').fetch(:top).map do |row|
      row.fetch(:full_name)
    end).to eq(%w[alice/app alice/lib])
    expect(store.pending_candidates(period)).to be_empty
  end

  it 'marks an already snapshotted pending candidate as processed' do
    store.upsert_user(user_attributes(1, 'alice'))
    store.record_user_stats(user_stats(1, 'alice'))
    store.record_candidate(period, github_id: 1, login: 'alice', source_query: 'Poland')

    job.call(period)

    expect(store.pending_candidates(period)).to be_empty
  end

  it 'marks missing users without failing the run' do
    github.candidates = { 'Poland' => [{ 'id' => 404, 'login' => 'missing' }] }
    github.missing_logins = ['missing']

    expect { job.call(period) }.not_to raise_error
    expect(store.pending_candidates(period)).to be_empty
  end

  it 'records candidate and run failures for retryable job crashes' do
    github.candidates = { 'Poland' => [{ 'id' => 500, 'login' => 'broken' }] }
    github.fail_logins = ['broken']

    expect { job.call(period) }.to raise_error(RuntimeError, 'boom')
    expect(store.pending_candidates(period)).to contain_exactly(include(login: 'broken'))
  end

  def profile(id, login, location, blog: 'https://example.com')
    {
      'id' => id,
      'login' => login,
      'name' => login.capitalize,
      'location' => location,
      'email' => "#{login}@example.com",
      'blog' => blog,
      'html_url' => "https://github.com/#{login}",
      'avatar_url' => "https://avatars.example/#{login}.png"
    }
  end

  def repository(id, full_name, stars, homepage: 'https://repo.example')
    {
      'id' => id,
      'name' => full_name.split('/').last,
      'full_name' => full_name,
      'description' => "Repository #{full_name}",
      'html_url' => "https://github.com/#{full_name}",
      'homepage' => homepage,
      'language' => 'Ruby',
      'fork' => false,
      'archived' => false,
      'stargazers_count' => stars
    }
  end

  def user_attributes(id, login)
    {
      github_id: id,
      login: login,
      name: login.capitalize,
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: nil,
      homepage: nil,
      html_url: "https://github.com/#{login}",
      avatar_url: nil
    }
  end

  def user_stats(id, login)
    {
      period_start: period.start_date.to_s,
      user_github_id: id,
      login: login,
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 0,
      total_stars: 0,
      monthly_stars_delta: 0,
      public_activity_count: 0
    }
  end
end

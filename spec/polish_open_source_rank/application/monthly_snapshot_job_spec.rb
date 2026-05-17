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

  def platform
    'github'
  end

  def user(login, _id = nil)
    raise 'boom' if fail_logins.include?(login)
    raise missing_error if missing_logins.include?(login)

    profiles.fetch(login)
  end

  def repositories_for(profile)
    repositories.fetch(profile.fetch(:login), [])
  end

  def repository_stars_delta(repository, _period)
    deltas.fetch(repository.fetch(:full_name), 0)
  end

  def public_activity_count(profile, _period)
    activities.fetch(profile.fetch(:login), 0)
  end

  private

  def missing_error
    PolishOpenSourceRank::Application::SourceNotFound.new('missing')
  end
end

class FakeJobGitLab < FakeJobGitHub
  def platform
    'gitlab'
  end

  private

  def missing_error
    PolishOpenSourceRank::Application::SourceNotFound.new('missing')
  end
end

class FakeJobCodeberg < FakeJobGitHub
  def platform
    'codeberg'
  end

  private

  def missing_error
    PolishOpenSourceRank::Application::SourceNotFound.new('missing')
  end
end

class BlockingDiscoverySource < FakeJobGitHub
  attr_reader :platform

  def initialize(platform, started, release)
    super()
    @platform = platform
    @started = started
    @release = release
  end

  def search_users_by_location(_term)
    @started << platform
    @release.pop
    []
  end
end

RSpec.describe PolishOpenSourceRank::Application::MonthlySnapshotJob do
  let(:period) { PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04') }
  let(:store) { PolishOpenSourceRank::Infrastructure::SQLiteStore.new(File.join(Dir.mktmpdir, 'job.sqlite3')).migrate! }
  let(:catalog) { double('catalog', search_terms: ['Poland']) }
  let(:github) { FakeJobGitHub.new }
  let(:job) { described_class.new(store: store, github: github, catalog: catalog, logger: StringIO.new) }

  it 'discovers candidates, rejects non-Polish profiles, and stores Polish snapshots' do
    github.candidates = {
      'Poland' => [{ source_id: 1, login: 'alice' }, { source_id: 2, login: 'bob' }]
    }
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
    github.candidates = { 'Poland' => [{ source_id: 404, login: 'missing' }] }
    github.missing_logins = ['missing']

    expect { job.call(period) }.not_to raise_error
    expect(store.pending_candidates(period)).to be_empty
  end

  it 'marks missing GitLab users without failing the run' do
    gitlab = FakeJobGitLab.new
    gitlab.candidates = { 'Poland' => [{ source_id: 404, login: 'missing' }] }
    gitlab.missing_logins = ['missing']

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(store.pending_candidates(period)).to be_empty
  end

  it 'stores Codeberg profiles through the normalized source contract' do
    codeberg = FakeJobCodeberg.new
    codeberg.candidates = { 'Poland' => [{ source_id: 3, login: 'celina' }] }
    codeberg.profiles = { 'celina' => codeberg_profile }
    codeberg.repositories = { 'celina' => [codeberg_repository] }

    described_class.new(store: store, sources: [codeberg], catalog: catalog, logger: StringIO.new).call(period)

    expect(store.user_rankings('warszawa').fetch(:top).first).to include(
      platform: 'codeberg',
      login: 'celina',
      name: 'Celina C',
      homepage: 'https://celina.example',
      total_stars: 9
    )
    expect(store.repository_rankings('warszawa').fetch(:top).first).to include(
      platform: 'codeberg',
      full_name: 'celina/tool',
      stargazers_count: 9
    )
  end

  it 'records candidate and run failures for retryable job crashes' do
    github.candidates = { 'Poland' => [{ source_id: 500, login: 'broken' }] }
    github.fail_logins = ['broken']

    expect { job.call(period) }.to raise_error(RuntimeError, 'boom')
    expect(store.pending_candidates(period)).to contain_exactly(include(login: 'broken'))
  end

  it 'discovers sources in parallel and writes platform-prefixed logs' do
    started = Queue.new
    release = Queue.new
    logger = StringIO.new
    sources = [
      BlockingDiscoverySource.new('github', started, release),
      BlockingDiscoverySource.new('gitlab', started, release)
    ]
    thread = Thread.new do
      described_class.new(store: store, sources: sources, catalog: catalog, logger: logger).call(period)
    end

    expect([started.pop, started.pop].sort).to eq(%w[github gitlab])
    2.times { release << true }
    thread.value

    expect(logger.string).to include('[github] discovering users for location "Poland"')
    expect(logger.string).to include('[gitlab] discovering users for location "Poland"')
  end

  def profile(id, login, location, blog: 'https://example.com')
    {
      source_id: id,
      login: login,
      name: login.capitalize,
      location: location,
      email: "#{login}@example.com",
      homepage: blog,
      html_url: "https://github.com/#{login}",
      avatar_url: "https://avatars.example/#{login}.png"
    }
  end

  def repository(id, full_name, stars, homepage: 'https://repo.example')
    {
      source_id: id,
      name: full_name.split('/').last,
      full_name: full_name,
      description: "Repository #{full_name}",
      html_url: "https://github.com/#{full_name}",
      homepage: homepage,
      language: 'Ruby',
      fork: false,
      archived: false,
      stars: stars
    }
  end

  def codeberg_profile
    {
      source_id: 3,
      login: 'celina',
      name: 'Celina C',
      location: 'Warsaw, Poland',
      email: nil,
      homepage: 'https://celina.example',
      html_url: 'https://codeberg.org/celina',
      avatar_url: nil
    }
  end

  def codeberg_repository
    {
      source_id: 30,
      name: 'tool',
      full_name: 'celina/tool',
      description: 'Codeberg tool',
      html_url: 'https://codeberg.org/celina/tool',
      homepage: 'https://tool.example',
      language: 'Ruby',
      fork: false,
      archived: false,
      stars: 9
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

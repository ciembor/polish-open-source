# frozen_string_literal: true

class RepositoryCollectorStore
  attr_reader :organization_snapshots, :snapshots

  def initialize(previous_repository_stars: {}, previous_organization_repository_stars: {})
    @snapshots = []
    @organization_snapshots = []
    @previous_repository_stars = previous_repository_stars
    @previous_organization_repository_stars = previous_organization_repository_stars
  end

  def record_repository_snapshot(snapshot)
    snapshots << snapshot
  end

  def record_organization_repository_snapshot(snapshot)
    organization_snapshots << snapshot
  end

  def previous_repository_stars(_period, platform:, repository_source_id:)
    @previous_repository_stars[[platform, repository_source_id]]
  end

  def previous_organization_repository_stars(_period, platform:, repository_source_id:)
    @previous_organization_repository_stars[[platform, repository_source_id]]
  end
end

class RepositoryCollectorMutex
  def synchronize
    yield
  end
end

class RepositoryCollectorWorkEvents
  attr_reader :events

  def initialize
    @events = []
  end

  def record_timed(**attributes)
    events << attributes
    yield
  end
end

class RepositoryCollectorSnapshotFactory
  def repository_snapshot(_period, _source, _profile, _location, repository, monthly_stars_delta)
    { full_name: repository.full_name, stars: repository.stars, monthly_stars_delta: monthly_stars_delta }
  end

  def organization_repository_snapshot(_period, _source, _profile, _location, repository, monthly_stars_delta)
    { full_name: repository.full_name, stars: repository.stars, monthly_stars_delta: monthly_stars_delta }
  end
end

class RepositoryCollectorAcceptedProfile
  attr_reader :period, :profile, :source

  def initialize(period:, source:, profile:)
    @period = period
    @source = source
    @profile = profile
  end

  def snapshot_args
    [period, source, profile, nil]
  end

  def source_platform
    source.platform
  end
end

class RepositoryCollectorSource
  attr_reader :organization_streams, :platform

  def initialize(repositories:, organization_repositories: {}, platform: 'github')
    @repositories = repositories
    @organization_repositories = organization_repositories
    @platform = platform
    @organization_streams = []
  end

  def repositories_for(profile)
    @repositories.fetch(profile.login, [])
  end

  def repositories_for_organization(_profile)
    raise 'organization repositories should be streamed'
  end

  def each_repository_for_organization(profile, &)
    organization_streams << profile.login
    @organization_repositories.fetch(profile.login, []).each(&)
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Application::MonthlyRepositorySnapshotCollector do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:mutex) { RepositoryCollectorMutex.new }
  let(:store) { RepositoryCollectorStore.new }
  let(:work_events) { RepositoryCollectorWorkEvents.new }
  let(:profile) { profile_record(1, 'alice') }

  it 'filters contributor repositories below the minimum star threshold' do
    source = RepositoryCollectorSource.new(
      repositories: { 'alice' => [repository(10, 'alice/tiny', 4), repository(11, 'alice/app', 5)] }
    )
    store = RepositoryCollectorStore.new(previous_repository_stars: { ['github', 11] => 3 })

    metrics = collector(store: store).contributor_metrics(accepted_profile(source: source, profile: profile))

    expect(metrics).to have_attributes(public_repository_count: 1, total_stars: 5, monthly_stars_delta: 2)
    expect(store.snapshots).to eq([{ full_name: 'alice/app', stars: 5, monthly_stars_delta: 2 }])
  end

  it 'stores zero-star repositories with a zero monthly delta when the ranking policy allows them' do
    source = RepositoryCollectorSource.new(repositories: { 'alice' => [repository(10, 'alice/empty', 0)] })

    metrics = collector(minimum_repository_stars: 0).contributor_metrics(
      accepted_profile(source: source, profile: profile)
    )

    expect(metrics).to have_attributes(public_repository_count: 1, total_stars: 0, monthly_stars_delta: 0)
    expect(store.snapshots).to eq([{ full_name: 'alice/empty', stars: 0, monthly_stars_delta: 0 }])
  end

  it 'uses previous stored repository observations for monthly stars' do
    source = RepositoryCollectorSource.new(repositories: { 'alice' => [repository(10, 'alice/app', 13)] })
    store = RepositoryCollectorStore.new(previous_repository_stars: { ['github', 10] => 10 })

    metrics = collector(store: store).contributor_metrics(accepted_profile(source: source, profile: profile))

    expect(metrics).to have_attributes(total_stars: 13, monthly_stars_delta: 3)
    expect(store.snapshots).to eq([{ full_name: 'alice/app', stars: 13, monthly_stars_delta: 3 }])
  end

  it 'does not report negative monthly stars when a repository loses stars' do
    source = RepositoryCollectorSource.new(repositories: { 'alice' => [repository(10, 'alice/app', 13)] })
    store = RepositoryCollectorStore.new(previous_repository_stars: { ['github', 10] => 15 })

    metrics = collector(store: store).contributor_metrics(accepted_profile(source: source, profile: profile))

    expect(metrics).to have_attributes(total_stars: 13, monthly_stars_delta: 0)
    expect(store.snapshots).to eq([{ full_name: 'alice/app', stars: 13, monthly_stars_delta: 0 }])
  end

  it 'streams organization repositories through the organization entry point' do
    organization = profile_record(9, 'polish-org')
    source = RepositoryCollectorSource.new(
      repositories: {},
      organization_repositories: { 'polish-org' => [repository(90, 'polish-org/toolkit', 9)] }
    )
    store = RepositoryCollectorStore.new(previous_organization_repository_stars: { ['github', 90] => 3 })

    metrics = collector(store: store).organization_metrics(accepted_profile(source: source, profile: organization))

    expect(metrics).to have_attributes(public_repository_count: 1, total_stars: 9, monthly_stars_delta: 6)
    expect(store.organization_snapshots).to eq([{ full_name: 'polish-org/toolkit', stars: 9, monthly_stars_delta: 6 }])
    expect(source.organization_streams).to eq(['polish-org'])
  end

  def collector(store: self.store, minimum_repository_stars: 5)
    described_class.new(
      store: store,
      store_mutex: mutex,
      work_events: work_events,
      minimum_repository_stars: minimum_repository_stars,
      snapshot_factory: RepositoryCollectorSnapshotFactory.new
    )
  end

  def accepted_profile(source:, profile:)
    RepositoryCollectorAcceptedProfile.new(
      period: period,
      source: source,
      profile: profile
    )
  end

  def profile_record(id, login)
    PolishOpenSourceRank::Contexts::Ranking::Domain::SourceContributor.new(
      source_id: id,
      login: login,
      location: 'Krakow, Poland',
      html_url: "https://github.com/#{login}"
    )
  end

  def repository(id, full_name, stars)
    PolishOpenSourceRank::Contexts::Ranking::Domain::SourceRepository.new(
      source_id: id,
      name: full_name.split('/').last,
      full_name: full_name,
      html_url: "https://github.com/#{full_name}",
      fork: false,
      archived: false,
      stars: stars
    )
  end
end

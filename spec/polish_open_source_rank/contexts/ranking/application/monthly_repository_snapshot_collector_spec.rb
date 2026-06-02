# frozen_string_literal: true

class RepositoryCollectorStore
  attr_reader :organization_snapshots, :snapshots

  def initialize(previous_contributor_stars: {}, previous_organization_stars: {})
    @previous_contributor_stars = previous_contributor_stars
    @previous_organization_stars = previous_organization_stars
    @snapshots = []
    @organization_snapshots = []
  end

  def previous_repository_stars(_period, _platform, source_id)
    @previous_contributor_stars[source_id]
  end

  def previous_organization_repository_stars(_period, _platform, source_id)
    @previous_organization_stars[source_id]
  end

  def record_repository_snapshot(snapshot)
    snapshots << snapshot
  end

  def record_organization_repository_snapshot(snapshot)
    organization_snapshots << snapshot
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

class RepositoryCollectorPreviousStars
  def initialize(store, mutex)
    @store = store
    @mutex = mutex
  end

  def contributor(period, platform, repository)
    mutex.synchronize { store.previous_repository_stars(period, platform, repository.source_id) }
  end

  def organization(period, platform, repository)
    mutex.synchronize { store.previous_organization_repository_stars(period, platform, repository.source_id) }
  end

  private

  attr_reader :mutex, :store
end

class RepositoryCollectorAcceptedProfile
  attr_reader :period, :previous_stars, :profile, :source

  def initialize(period:, source:, profile:, previous_stars:, use_snapshot_star_diff:)
    @period = period
    @source = source
    @profile = profile
    @previous_stars = previous_stars
    @use_snapshot_star_diff = use_snapshot_star_diff
  end

  def snapshot_args
    [period, source, profile, nil]
  end

  def source_platform
    source.platform
  end

  def use_snapshot_star_diff?
    @use_snapshot_star_diff
  end
end

class RepositoryCollectorSource
  attr_reader :delta_calls, :organization_streams, :platform

  def initialize(repositories:, organization_repositories: {}, deltas: {}, platform: 'github')
    @repositories = repositories
    @organization_repositories = organization_repositories
    @deltas = deltas
    @platform = platform
    @delta_calls = []
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

  def repository_stars_delta(repository, period)
    delta_calls << [repository.full_name, period]
    @deltas.fetch(repository.full_name)
  end
end

class RepositoryCollectorHistoricalSource < RepositoryCollectorSource
  attr_reader :star_snapshot_calls

  def initialize(star_snapshots:, **attributes)
    super(**attributes)
    @star_snapshots = star_snapshots
    @star_snapshot_calls = []
  end

  def repository_star_snapshot(repository, period)
    star_snapshot_calls << [repository.full_name, period]
    @star_snapshots.fetch(repository.full_name)
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
      repositories: { 'alice' => [repository(10, 'alice/tiny', 4), repository(11, 'alice/app', 5)] },
      deltas: { 'alice/app' => 2 }
    )

    metrics = collector.contributor_metrics(accepted_profile(source: source, profile: profile))

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
    expect(source.delta_calls).to be_empty
  end

  it 'uses stored snapshot diffs when requested and previous stars exist' do
    previous_store = RepositoryCollectorStore.new(previous_contributor_stars: { 10 => 8 })
    source = RepositoryCollectorSource.new(
      repositories: { 'alice' => [repository(10, 'alice/app', 13)] },
      deltas: { 'alice/app' => 99 }
    )

    metrics = collector(store: previous_store).contributor_metrics(
      accepted_profile(source: source, profile: profile, store: previous_store, use_snapshot_star_diff: true)
    )

    expect(metrics).to have_attributes(total_stars: 13, monthly_stars_delta: 5)
    expect(source.delta_calls).to be_empty
  end

  it 'uses source-provided deltas when stored snapshot diffs are not requested' do
    previous_store = RepositoryCollectorStore.new(previous_contributor_stars: { 10 => 8 })
    source = RepositoryCollectorSource.new(
      repositories: { 'alice' => [repository(10, 'alice/app', 13)] },
      deltas: { 'alice/app' => 3 }
    )

    metrics = collector(store: previous_store).contributor_metrics(
      accepted_profile(source: source, profile: profile, store: previous_store)
    )

    expect(metrics).to have_attributes(total_stars: 13, monthly_stars_delta: 3)
    expect(source.delta_calls).to eq([['alice/app', period]])
  end

  it 'stores source-provided historical star snapshots' do
    source = RepositoryCollectorHistoricalSource.new(
      repositories: { 'alice' => [repository(10, 'alice/app', 13)] },
      star_snapshots: { 'alice/app' => { stars: 11, monthly_stars_delta: 4 } }
    )

    metrics = collector.contributor_metrics(accepted_profile(source: source, profile: profile))

    expect(metrics).to have_attributes(total_stars: 11, monthly_stars_delta: 4)
    expect(store.snapshots).to eq([{ full_name: 'alice/app', stars: 11, monthly_stars_delta: 4 }])
    expect(source.star_snapshot_calls).to eq([['alice/app', period]])
    expect(source.delta_calls).to be_empty
  end

  it 'streams organization repositories through the organization entry point' do
    organization = profile_record(9, 'polish-org')
    source = RepositoryCollectorSource.new(
      repositories: {},
      organization_repositories: { 'polish-org' => [repository(90, 'polish-org/toolkit', 9)] },
      deltas: { 'polish-org/toolkit' => 6 }
    )

    metrics = collector.organization_metrics(accepted_profile(source: source, profile: organization))

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

  def accepted_profile(source:, profile:, store: self.store, use_snapshot_star_diff: false)
    RepositoryCollectorAcceptedProfile.new(
      period: period,
      source: source,
      profile: profile,
      previous_stars: RepositoryCollectorPreviousStars.new(store, mutex),
      use_snapshot_star_diff: use_snapshot_star_diff
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

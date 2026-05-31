# frozen_string_literal: true

require 'fileutils'
require 'timeout'
require 'tmpdir'

class FakeJobGitHub
  attr_accessor :activities, :candidates, :deltas, :fail_errors, :fail_logins, :missing_logins, :profiles,
                :repositories, :organization_candidates, :organization_fail_errors, :organization_fail_logins,
                :organization_missing_logins, :organizations, :organization_repositories, :merged_pull_requests,
                :organization_members
  attr_reader :activity_periods, :delta_periods, :searched_terms, :user_calls, :organization_calls,
              :merged_pull_request_periods, :organization_member_calls

  def initialize
    @activity_periods = []
    @activities = {}
    @candidates = {}
    @delta_periods = []
    @deltas = {}
    @fail_errors = {}
    @fail_logins = []
    @missing_logins = []
    @profiles = {}
    @repositories = {}
    @merged_pull_requests = {}
    @organization_candidates = {}
    @organization_fail_errors = {}
    @organization_fail_logins = []
    @organization_missing_logins = []
    @organizations = {}
    @organization_repositories = {}
    @organization_members = {}
    @searched_terms = []
    @user_calls = []
    @organization_calls = []
    @merged_pull_request_periods = []
    @organization_member_calls = []
  end

  def search_users_by_location(term)
    searched_terms << term
    candidates.fetch(term, [])
  end

  def platform
    'github'
  end

  def supports_organizations?
    false
  end

  def user(login, id = nil)
    user_calls << [login, id]
    raise fail_errors.fetch(login) if fail_errors.key?(login)
    raise 'boom' if fail_logins.include?(login)
    raise missing_error if missing_logins.include?(login)

    profiles.fetch(login)
  end

  def search_organizations_by_location(term)
    searched_terms << "org:#{term}"
    organization_candidates.fetch(term, [])
  end

  def organization(login, id = nil)
    organization_calls << [login, id]
    raise organization_fail_errors.fetch(login) if organization_fail_errors.key?(login)
    raise 'boom' if organization_fail_logins.include?(login)
    raise missing_error if organization_missing_logins.include?(login)

    organizations.fetch(login)
  end

  def repositories_for(profile)
    repositories.fetch(profile.fetch(:login), [])
  end

  def repositories_for_organization(profile)
    organization_repositories.fetch(profile.fetch(:login), [])
  end

  def repository_stars_delta(repository, period)
    delta_periods << [repository.fetch(:full_name), period]
    deltas.fetch(repository.fetch(:full_name), 0)
  end

  def public_activity_count(profile, period)
    activity_periods << [profile.fetch(:login), period]
    activities.fetch(profile.fetch(:login), 0)
  end

  def merged_pull_requests_count(profile, period)
    merged_pull_request_periods << [profile.fetch(:login), period]
    merged_pull_requests.fetch(profile.fetch(:login), 0)
  end

  def organization_members_count(profile)
    organization_member_calls << profile.fetch(:login)
    organization_members.fetch(profile.fetch(:login), 0)
  end

  private

  def missing_error
    PolishOpenSourceRank::Contexts::Ranking::Application::SourceNotFound.new('missing')
  end
end

class FakeJobGitLab < FakeJobGitHub
  def platform
    'gitlab'
  end

  private

  def missing_error
    PolishOpenSourceRank::Contexts::Ranking::Application::SourceNotFound.new('missing')
  end
end

class FakeJobCodeberg < FakeJobGitHub
  def platform
    'codeberg'
  end

  private

  def missing_error
    PolishOpenSourceRank::Contexts::Ranking::Application::SourceNotFound.new('missing')
  end
end

class JoinInterruptedThread
  attr_reader :killed

  def initialize(error)
    @error = error
    @join_calls = 0
    @killed = false
  end

  def join
    @join_calls += 1
    raise error if @join_calls == 1

    self
  end

  def [](_key)
    nil
  end

  def alive?
    !killed
  end

  def killed?
    killed
  end

  def kill
    @killed = true
  end

  private

  attr_reader :error
end

class FakeOrganizationGitHub < FakeJobGitHub
  def supports_organizations?
    true
  end
end

class HistoricalStarGitHub < FakeJobGitHub
  attr_accessor :star_snapshots
  attr_reader :star_snapshot_periods

  def initialize
    super
    @star_snapshot_periods = []
    @star_snapshots = {}
  end

  def repository_star_snapshot(repository, period)
    star_snapshot_periods << [repository.fetch(:full_name), period]
    star_snapshots.fetch(repository.fetch(:full_name))
  end
end

class HistoricalStarOrganizationGitHub < HistoricalStarGitHub
  def supports_organizations?
    true
  end
end

class StreamingOrganizationGitHub < FakeOrganizationGitHub
  def repositories_for_organization(_profile)
    raise 'organization repositories should be streamed'
  end

  def each_repository_for_organization(profile, &)
    organization_repositories.fetch(profile.fetch(:login), []).each(&)
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

class BlockingCandidateDiscoverySource < FakeJobGitHub
  attr_reader :platform

  def initialize(platform, started, release, candidate)
    super()
    @platform = platform
    @started = started
    @release = release
    @candidate = candidate
  end

  def search_users_by_location(_term)
    @started << platform
    @release.pop
    [@candidate]
  end
end

class FailingDiscoverySource < FakeJobGitHub
  attr_reader :platform

  def initialize(platform, error: RuntimeError.new('discovery failed'))
    super()
    @platform = platform
    @error = error
  end

  def search_users_by_location(_term)
    raise @error
  end
end

class DistinctToStringError < StandardError
  attr_reader :message

  def initialize(message)
    @message = message
    super
  end

  def to_s
    'custom to_s'
  end
end

class FailingCreateRunStore
  def create_run(...)
    raise 'database unavailable'
  end

  def fail_run(_run_id, _error)
    raise 'run should not be failed before it exists'
  end
end

class FailingPendingCandidatesStore
  def initialize(store)
    @store = store
  end

  def pending_candidates(*)
    raise 'pending failed'
  end

  def method_missing(name, ...)
    @store.public_send(name, ...)
  end

  def respond_to_missing?(name, include_private = false)
    @store.respond_to?(name, include_private) || super
  end
end

class ConcurrentWriteDetectingStore
  attr_reader :concurrent_write

  def initialize(store)
    @store = store
    @writing = false
    @concurrent_write = false
  end

  def record_candidate(...)
    guarded_write { @store.record_candidate(...) }
  end

  def record_contributor_snapshot(...)
    guarded_write { @store.record_contributor_snapshot(...) }
  end

  def record_repository_snapshot(...)
    guarded_write { @store.record_repository_snapshot(...) }
  end

  def mark_candidate(...)
    guarded_write { @store.mark_candidate(...) }
  end

  def pending_candidates(...)
    guarded_write { @store.pending_candidates(...) }
  end

  def processed_user?(...)
    guarded_write { @store.processed_user?(...) }
  end

  def record_repository_stats(...)
    guarded_write { @store.record_repository_stats(...) }
  end

  def record_user_stats(...)
    guarded_write { @store.record_user_stats(...) }
  end

  def upsert_repository(...)
    guarded_write { @store.upsert_repository(...) }
  end

  def upsert_user(...)
    guarded_write { @store.upsert_user(...) }
  end

  def method_missing(name, ...)
    @store.public_send(name, ...)
  end

  def respond_to_missing?(name, include_private = false)
    @store.respond_to?(name, include_private) || super
  end

  private

  def guarded_write
    @concurrent_write = true if @writing
    @writing = true
    sleep 0.02
    yield
  ensure
    @writing = false
  end
end

class FlushTrackingLogger
  attr_reader :flushes, :lines

  def initialize
    @flushes = 0
    @lines = []
  end

  def puts(line)
    @lines << line
  end

  def flush
    @flushes += 1
  end
end

class NoFlushLogger
  def puts(_line); end
end

class SinglePendingCandidateStore
  attr_reader :marked_candidates

  def initialize(candidate)
    @candidate = candidate
    @marked_candidates = []
    @pending_returned = false
  end

  def create_run(...)
    1
  end

  def retryable_candidates?(*)
    false
  end

  def record_candidate(*); end

  def pending_candidates(_period, platform:, limit:)
    return [] if @pending_returned || platform != @candidate.fetch(:platform) || limit != 50

    @pending_returned = true
    [@candidate]
  end

  def processed_user?(*)
    false
  end

  def upsert_user(*); end

  def record_contributor_profile(*); end

  def record_contributor_snapshot(*); end

  def record_repository_snapshot(*); end

  def record_user_stats(*); end

  def mark_candidate(*args)
    @marked_candidates << args
  end

  def prune_rankings(_period); end

  def finish_run(_run_id); end
end

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:store) do
    PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore.new(
      run_repository: run_repository,
      candidate_queue: candidate_queue,
      snapshot_repository: snapshot_repository,
      ranking_retention: ranking_retention
    )
  end
  let(:catalog) { double('catalog', search_terms: ['Poland']) }
  let(:github) { FakeJobGitHub.new }
  let(:path) { File.join(@tmpdir, 'job.sqlite3') }

  before do
    @tmpdir = Dir.mktmpdir('polish-open-source-rank-spec-')
  end

  after do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  it 'discovers candidates, rejects non-Polish profiles, and stores Polish snapshots' do
    seed_alice_and_bob_discovery
    github.deltas = { 'alice/app' => 3, 'alice/lib' => 1 }
    github.activities = { 'alice' => 7 }
    allow(store).to receive(:prune_rankings).and_call_original

    job.call(period)

    expect(store).to have_received(:prune_rankings).with(period)
    expect(user_rankings('poland').fetch(:trending).first).to include(login: 'alice', monthly_stars_delta: 4)
    expect(user_rankings('krakow').fetch(:active).first).to include(merged_pull_requests_count: 0)
    expect(repository_rankings('poland').fetch(:top).map do |row|
      row.fetch(:full_name)
    end).to eq(%w[alice/app alice/lib])
    expect(store.pending_candidates(period)).to be_empty
    expect_finished_run
    expect_persisted_alice_profile
    expect_persisted_alice_stats
    expect_persisted_alice_repositories
    expect_persisted_alice_repository_stats
    expect(github.user_calls).to eq([['alice', 1], ['bob', 2]])
    expect(github.delta_periods).to eq([['alice/app', period], ['alice/lib', period]])
    expect(github.activity_periods).to be_empty
  end

  it 'uses previous repository observations and skips repositories below the catalog star threshold' do
    previous_period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-03')
    seed_previous_repository_observation(previous_period)
    github.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    github.repositories = {
      'alice' => [
        repository(10, 'alice/app', 14),
        repository(11, 'alice/new', 7),
        repository(12, 'alice/empty', 0)
      ]
    }
    github.deltas = { 'alice/new' => 2 }

    job.call(period)

    expect(fetch_user_stats('alice')).to include(monthly_stars_delta: 6)
    expect(fetch_repository_stats('alice/app')).to include(monthly_stars_delta: 4)
    expect(fetch_repository_stats('alice/new')).to include(monthly_stars_delta: 2)
    expect(fetch_repository_stats('alice/empty')).to be_nil
    expect(github.delta_periods).to eq([['alice/new', period]])
  end

  it 'stores source-provided historical repository star snapshots' do
    source = HistoricalStarGitHub.new
    source.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    source.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    source.repositories = { 'alice' => [repository(10, 'alice/app', 12)] }
    source.star_snapshots = {
      'alice/app' => { stars: 9, monthly_stars_delta: 3 }
    }

    run_job_with(source: source)

    expect(fetch_user_stats('alice')).to include(total_stars: 9, monthly_stars_delta: 3)
    expect(fetch_repository_stats('alice/app')).to include(stargazers_count: 9, monthly_stars_delta: 3)
    expect(source.star_snapshot_periods).to eq([['alice/app', period]])
    expect(source.delta_periods).to be_empty
  end

  it 'can recalculate repository star deltas from source history during a refresh' do
    previous_period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-03')
    seed_previous_repository_observation(previous_period)
    github.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    github.repositories = { 'alice' => [repository(10, 'alice/app', 14)] }
    github.deltas = { 'alice/app' => 9 }

    job.call(period, refresh: true, recalculate_stars: true)

    expect(fetch_user_stats('alice')).to include(monthly_stars_delta: 9)
    expect(fetch_repository_stats('alice/app')).to include(monthly_stars_delta: 9)
    expect(github.delta_periods).to eq([['alice/app', period]])
  end

  it 'runs only the organization pipeline when scoped to organizations' do
    organization_source = FakeOrganizationGitHub.new
    organization_source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    organization_source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    organization_source.organization_repositories = { 'polish-org' => [repository(90, 'polish-org/toolkit', 33)] }
    seed_alice_and_bob_discovery

    described_class.new(store: store, sources: [organization_source], catalog: catalog, logger: StringIO.new).call(
      period,
      scope: :organizations
    )

    expect(organization_source.user_calls).to be_empty
    expect(fetch_candidate('alice')).to be_nil
    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to include(status: 'processed', error: nil)
    expect(fetch_user('polish-org', table: 'organizations')).to include(login: 'polish-org')
  end

  it 'stores monthly merged pull requests and organization members in snapshots' do
    source = FakeOrganizationGitHub.new
    source.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    source.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    source.repositories = { 'alice' => [repository(10, 'alice/app', 12)] }
    source.activities = { 'alice' => 7 }
    source.merged_pull_requests = { 'alice' => 5 }
    source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    source.organization_repositories = { 'polish-org' => [repository(20, 'polish-org/toolkit', 8)] }
    source.organization_members = { 'polish-org' => 14 }

    run_job_with(source: source)

    expect(fetch_user_stats('alice')).to include(merged_pull_requests_count: 5)
    expect(fetch_organization_stats('polish-org')).to include(members_count: 14)
  end

  it 'refreshes merged pull requests for existing users without rerunning discovery' do
    upsert_user(user_attributes(1, 'alice'))
    record_user_stats(user_stats(1, 'alice'))
    github.merged_pull_requests = { 'alice' => 11 }

    described_class.new(store: store, sources: [github], catalog: catalog, logger: StringIO.new).call(
      period,
      existing_only: true,
      backfill: { refresh_user_merged_prs: true }
    )

    expect(fetch_user_stats('alice')).to include(merged_pull_requests_count: 11)
    expect(github.searched_terms).to eq([])
  end

  it 'refreshes organization members for existing organizations without rediscovery' do
    snapshot_repository.record_organization_snapshot(organization_snapshot_record(period))
    organization_source = FakeOrganizationGitHub.new
    organization_source.organization_members = { 'polish-org' => 23 }

    described_class.new(
      store: store,
      sources: [organization_source],
      catalog: catalog,
      logger: StringIO.new
    ).call(
      period,
      scope: :organizations,
      existing_only: true,
      backfill: { refresh_organization_members: true }
    )

    expect(fetch_organization_stats('polish-org')).to include(members_count: 23)
  end

  it 'does not fail an organization-scoped run because user candidates remain retryable' do
    organization_source = FakeOrganizationGitHub.new
    organization_source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    organization_source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    organization_source.organization_repositories = { 'polish-org' => [repository(90, 'polish-org/toolkit', 33)] }
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland')

    described_class.new(store: store, sources: [organization_source], catalog: catalog, logger: StringIO.new).call(
      period,
      scope: :organizations
    )

    expect(fetch_candidate('alice')).to include(status: 'pending')
    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to include(status: 'processed', error: nil)
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'running',
      error: nil
    )
  end

  it 'runs only the user pipeline when scoped to users' do
    organization_source = FakeOrganizationGitHub.new
    organization_source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    organization_source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    organization_source.candidates = {
      'Poland' => [{ source_id: 1, login: 'alice' }, { source_id: 2, login: 'bob' }]
    }
    organization_source.profiles = {
      'alice' => profile(1, 'alice', 'Krakow, Poland', blog: ''),
      'bob' => profile(2, 'bob', 'Berlin, Germany')
    }
    organization_source.repositories = {
      'alice' => [
        repository(10, 'alice/app', 12),
        repository(11, 'alice/lib', 5, homepage: '', fork: true, archived: true)
      ]
    }

    described_class.new(store: store, sources: [organization_source], catalog: catalog, logger: StringIO.new).call(
      period,
      scope: :users
    )

    expect(organization_source.user_calls).to eq([['alice', 1], ['bob', 2]])
    expect(organization_source.organization_calls).to be_empty
    expect(fetch_candidate('alice')).to include(status: 'processed', error: nil)
    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to be_nil
    expect(fetch_user('polish-org', table: 'organizations')).to be_nil
  end

  it 'processes existing pending user candidates before discovering more' do
    source = FakeJobGitHub.new
    source.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    source.profiles = {
      'alice' => profile(1, 'alice', 'Krakow, Poland'),
      'bob' => profile(2, 'bob', 'Warsaw, Poland')
    }
    source.repositories = { 'alice' => [], 'bob' => [] }
    store.record_candidate(period, platform: 'github', source_id: 2, login: 'bob', source_query: 'Poland')

    described_class.new(store: store, sources: [source], catalog: catalog, logger: StringIO.new).call(period)

    expect(source.user_calls).to eq([['bob', 2], ['alice', 1]])
    expect(fetch_candidate('bob')).to include(status: 'processed', error: nil)
    expect(fetch_candidate('alice')).to include(status: 'processed', error: nil)
  end

  it 'can process existing pending user candidates without discovering more' do
    source = FakeJobGitHub.new
    source.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    source.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    source.repositories = { 'bob' => [] }
    store.record_candidate(period, platform: 'github', source_id: 2, login: 'bob', source_query: 'Poland')

    described_class.new(store: store, sources: [source], catalog: catalog, logger: StringIO.new).call(
      period,
      existing_only: true
    )

    expect(source.searched_terms).to be_empty
    expect(source.user_calls).to eq([['bob', 2]])
    expect(fetch_candidate('bob')).to include(status: 'processed', error: nil)
    expect(fetch_candidate('alice')).to be_nil
  end

  it 'discovers organizations, stores organization rankings, and persists organization repositories' do
    organization_source = ranked_organization_source

    run_job_with(source: organization_source)

    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to include(status: 'processed', error: nil)
    expect(fetch_row('SELECT login, total_stars FROM organization_monthly_stats')).to include(
      login: 'polish-org',
      total_stars: 33
    )
    expect(fetch_row(<<~SQL)).to include(full_name: 'polish-org/toolkit', stargazers_count: 33)
      SELECT repositories.full_name, stats.stargazers_count
      FROM organization_repository_monthly_stats stats
      INNER JOIN organization_repositories repositories
        ON repositories.platform = stats.platform
       AND repositories.github_id = stats.repository_github_id
    SQL
    expect(organization_rankings.fetch(:top).first).to include(login: 'polish-org', total_stars: 33)
    expect(organization_repository_rankings.fetch(:trending).first).to include(
      full_name: 'polish-org/toolkit',
      monthly_stars_delta: 6
    )
    expect(organization_source.organization_calls).to eq([['polish-org', 9]])
  end

  it 'stores source-provided historical organization repository star snapshots' do
    organization_source = HistoricalStarOrganizationGitHub.new
    organization_source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    organization_source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    organization_source.organization_repositories = { 'polish-org' => [repository(90, 'polish-org/toolkit', 33)] }
    organization_source.star_snapshots = {
      'polish-org/toolkit' => { stars: 27, monthly_stars_delta: 4 }
    }

    run_job_with(source: organization_source)

    expect(fetch_row('SELECT total_stars, monthly_stars_delta FROM organization_monthly_stats'))
      .to include(total_stars: 27, monthly_stars_delta: 4)
    expect(fetch_row(<<~SQL)).to include(stargazers_count: 27, monthly_stars_delta: 4)
      SELECT stats.stargazers_count, stats.monthly_stars_delta
      FROM organization_repository_monthly_stats stats
      INNER JOIN organization_repositories repositories
        ON repositories.platform = stats.platform
       AND repositories.github_id = stats.repository_github_id
      WHERE repositories.full_name = 'polish-org/toolkit'
    SQL
    expect(organization_source.star_snapshot_periods).to eq([['polish-org/toolkit', period]])
    expect(organization_source.delta_periods).to be_empty
  end

  def ranked_organization_source
    FakeOrganizationGitHub.new.tap do |source|
      source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
      source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
      source.organization_repositories = { 'polish-org' => [repository(90, 'polish-org/toolkit', 33)] }
      source.deltas = { 'polish-org/toolkit' => 6 }
    end
  end

  it 'streams organization repositories while calculating organization metrics' do
    organization_source = StreamingOrganizationGitHub.new
    organization_source.organization_candidates = { 'Poland' => [{ source_id: 9, login: 'polish-org' }] }
    organization_source.organizations = { 'polish-org' => profile(9, 'polish-org', 'Warsaw, Poland') }
    organization_source.organization_repositories = {
      'polish-org' => [
        repository(90, 'polish-org/toolkit', 33),
        repository(91, 'polish-org/docs', 7)
      ]
    }
    organization_source.deltas = { 'polish-org/toolkit' => 6, 'polish-org/docs' => 2 }

    run_job_with(source: organization_source)

    expect(fetch_row('SELECT public_repo_count, total_stars, monthly_stars_delta FROM organization_monthly_stats'))
      .to include(public_repo_count: 2, total_stars: 40, monthly_stars_delta: 8)
    expect(organization_repository_rankings.fetch(:top).map { |row| row.fetch(:full_name) }).to eq(
      ['polish-org/toolkit', 'polish-org/docs']
    )
  end

  it 'marks an already snapshotted pending candidate as processed' do
    upsert_user(user_attributes(1, 'alice'))
    record_user_stats(user_stats(1, 'alice'))
    store.record_candidate(period, github_id: 1, login: 'alice', source_query: 'Poland')
    allow(store).to receive(:pending_candidates).and_call_original

    job.call(period)

    expect(store).to have_received(:pending_candidates).with(
      period,
      platform: 'github',
      limit: described_class::BATCH_SIZE
    ).at_least(:once)
    expect(store.pending_candidates(period)).to be_empty
    expect(fetch_candidate('alice')).to include(status: 'processed', error: nil)
  end

  it 'marks already snapshotted organizations on their source platform' do
    organization_source = FakeOrganizationGitHub.new
    store.record_organization_candidate(period, platform: 'github', source_id: 9, login: 'polish-org',
                                                source_query: 'Poland')
    snapshot_repository.record_organization_snapshot(organization_snapshot_record(period))

    run_job_with(source: organization_source)

    expect(organization_source.organization_calls).to be_empty
    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to include(status: 'processed', error: nil)
  end

  it 'marks missing organizations without failing the run' do
    organization_source = FakeOrganizationGitHub.new
    store.record_organization_candidate(period, platform: 'github', source_id: 9, login: 'missing-org',
                                                source_query: 'Poland')
    organization_source.organization_missing_logins = ['missing-org']

    run_job_with(source: organization_source)

    expect(fetch_candidate('missing-org', table: 'candidate_organizations')).to include(status: 'missing', error: nil)
  end

  it 'rejects organizations outside Poland' do
    organization_source = FakeOrganizationGitHub.new
    store.record_organization_candidate(period, platform: 'github', source_id: 9, login: 'foreign-org',
                                                source_query: 'Poland')
    organization_source.organizations = { 'foreign-org' => profile(9, 'foreign-org', 'Berlin, Germany') }

    run_job_with(source: organization_source)

    expect(fetch_candidate('foreign-org', table: 'candidate_organizations')).to include(status: 'rejected', error: nil)
  end

  it 'records organization candidate failures and keeps processing later organizations' do
    organization_source = FakeOrganizationGitHub.new
    organization_source.organization_candidates = {
      'Poland' => [{ source_id: 9, login: 'broken-org' }, { source_id: 10, login: 'polish-org' }]
    }
    organization_source.organization_fail_logins = ['broken-org']
    organization_source.organizations = { 'polish-org' => profile(10, 'polish-org', 'Warsaw, Poland') }
    organization_source.organization_repositories = { 'polish-org' => [] }

    run_job_with(source: organization_source)

    expect(fetch_candidate('broken-org', table: 'candidate_organizations')).to include(status: 'failed')
    expect(fetch_candidate('polish-org', table: 'candidate_organizations')).to include(status: 'processed', error: nil)
  end

  it 'checks already snapshotted candidates within their source platform' do
    gitlab = FakeJobGitLab.new
    upsert_user(user_attributes(1, 'alice').merge(platform: 'github'))
    record_user_stats(user_stats(1, 'alice').merge(platform: 'github'))
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')
    gitlab.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    gitlab.repositories = { 'alice' => [] }

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(gitlab.user_calls).to eq([['alice', 1]])
    expect(fetch_candidate('alice', platform: 'gitlab')).to include(status: 'processed', error: nil)
  end

  it 'marks already snapshotted candidates on their source platform' do
    gitlab = FakeJobGitLab.new
    upsert_user(user_attributes(1, 'alice').merge(platform: 'gitlab'))
    record_user_stats(user_stats(1, 'alice').merge(platform: 'gitlab'))
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(gitlab.user_calls).to be_empty
    expect(fetch_candidate('alice', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect_finished_run
  end

  it 'reprocesses already snapshotted candidates during an explicit refresh' do
    gitlab = FakeJobGitLab.new
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')
    upsert_user(user_attributes(1, 'alice').merge(platform: 'gitlab'))
    record_user_stats(user_stats(1, 'alice').merge(platform: 'gitlab'))
    store.mark_candidate(period, 'gitlab', 'alice', 'processed')
    gitlab.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    gitlab.repositories = { 'alice' => [] }

    described_class.new(
      store: store,
      sources: [gitlab],
      catalog: double('catalog', search_terms: []),
      logger: StringIO.new
    ).call(period, refresh: true)

    expect(gitlab.user_calls).to eq([['alice', 1]])
    expect(fetch_candidate('alice', platform: 'gitlab')).to include(status: 'processed', error: nil)
  end

  it 'leaves the run open when other platforms still have retryable candidates' do
    gitlab = FakeJobGitLab.new
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland')

    described_class.new(
      store: store,
      sources: [gitlab],
      catalog: double('catalog', search_terms: []),
      logger: StringIO.new
    ).call(period)

    run = fetch_row('SELECT status, finished_at, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])
    expect(run).to include(
      status: 'running',
      finished_at: nil,
      error: nil
    )
  end

  it 'skips candidate discovery when the period is already finished' do
    run_id = store.create_run(period)
    store.finish_run(run_id)

    job.call(period)

    expect(github.searched_terms).to be_empty
    expect(fetch_row('SELECT status FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'finished'
    )
  end

  it 'uses production defaults for catalog and logger' do
    expect do
      described_class.new(store: store, sources: [github]).call(period)
    end.to output(/\[github\] candidate discovery finished/).to_stdout
  end

  it 'repeats idempotent discovery when resuming retryable candidates' do
    run_id = store.create_run(period)
    store.record_candidate(period, github_id: 1, login: 'alice', source_query: 'Poland')
    store.finish_run(run_id)
    github.candidates = { 'Poland' => [{ source_id: 1, login: 'alice' }] }
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }

    job.call(period)

    expect(github.searched_terms).to eq(['Poland'])
    expect(fetch_candidate('alice')).to include(status: 'processed', error: nil)
  end

  it 'marks missing users without failing the run' do
    github.candidates = { 'Poland' => [{ source_id: 404, login: 'missing' }] }
    github.missing_logins = ['missing']

    expect { job.call(period) }.not_to raise_error
    expect(store.pending_candidates(period)).to be_empty
    expect(fetch_candidate('missing')).to include(status: 'missing', error: nil)
  end

  it 'marks missing GitLab users without failing the run' do
    gitlab = FakeJobGitLab.new
    gitlab.candidates = { 'Poland' => [{ source_id: 404, login: 'missing' }] }
    gitlab.missing_logins = ['missing']

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(store.pending_candidates(period)).to be_empty
    expect(fetch_candidate('missing', platform: 'gitlab')).to include(status: 'missing', error: nil)
  end

  it 'rejects profiles without a location field' do
    github.candidates = { 'Poland' => [{ source_id: 404, login: 'no-location' }] }
    github.profiles = {
      'no-location' => { source_id: 404, login: 'no-location', html_url: 'https://github.com/no-location' }
    }

    job.call(period)

    expect(fetch_candidate('no-location')).to include(status: 'rejected', error: nil)
    expect_finished_run
  end

  it 'rejects profiles on their source platform' do
    gitlab = FakeJobGitLab.new
    gitlab.candidates = { 'Poland' => [{ source_id: 404, login: 'outsider' }] }
    gitlab.profiles = { 'outsider' => profile(404, 'outsider', 'Berlin, Germany') }

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(fetch_candidate('outsider', platform: 'gitlab')).to include(status: 'rejected', error: nil)
    expect_finished_run
  end

  it 'stores Codeberg profiles through the normalized source contract' do
    codeberg = FakeJobCodeberg.new
    codeberg.candidates = { 'Poland' => [{ source_id: 3, login: 'celina' }] }
    codeberg.profiles = { 'celina' => codeberg_profile }
    codeberg.repositories = { 'celina' => [codeberg_repository] }

    described_class.new(store: store, sources: [codeberg], catalog: catalog, logger: StringIO.new).call(period)

    expect(user_rankings('warszawa').fetch(:top).first).to include(
      platform: 'codeberg',
      login: 'celina',
      name: 'Celina C',
      homepage: 'https://celina.example',
      total_stars: 9
    )
    expect(repository_rankings('warszawa').fetch(:top).first).to include(
      platform: 'codeberg',
      full_name: 'celina/tool',
      stargazers_count: 9
    )
    expect(fetch_repository('celina/tool', platform: 'codeberg')).to include(
      description: 'Codeberg tool',
      homepage: 'https://tool.example',
      language: 'Ruby',
      fork: 0,
      archived: 0
    )
  end

  it 'reprocesses processed candidates when repository stats are missing from a previous run' do
    run_id = store.create_run(period)
    store.record_candidate(period, platform: 'gitlab', source_id: 2, login: 'bob', source_query: 'Poland')
    upsert_user(user_attributes(2, 'bob').merge(platform: 'gitlab'))
    record_user_stats(user_stats(2, 'bob').merge(platform: 'gitlab', public_repo_count: 1, total_stars: 5))
    store.mark_candidate(period, 'gitlab', 'bob', 'processed')
    store.finish_run(run_id)
    gitlab = FakeJobGitLab.new
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 5)] }

    described_class.new(
      store: store,
      sources: [gitlab],
      catalog: double('catalog', search_terms: []),
      logger: StringIO.new
    ).call(period)

    expect(fetch_candidate('bob', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect(fetch_repository_stats('bob/tool', platform: 'gitlab')).to include(
      owner_login: 'bob',
      stargazers_count: 5
    )
    expect_finished_run
  end

  it 'accepts missing and blank optional source fields' do
    github.candidates = { 'Poland' => [{ source_id: 3, login: 'optional' }] }
    github.profiles = { 'optional' => optional_profile }
    github.repositories = { 'optional' => [optional_repository] }

    job.call(period)

    expect(fetch_user('optional')).to include(name: nil, email: nil, homepage: nil, avatar_url: nil)
    expect(fetch_repository('optional/tool')).to include(description: nil, homepage: nil, language: nil)
  end

  it 'records candidate and run failures for retryable candidate crashes' do
    github.candidates = { 'Poland' => [{ source_id: 500, login: 'broken' }] }
    github.fail_errors = { 'broken' => DistinctToStringError.new('boom') }
    logger = StringIO.new

    expect do
      described_class.new(store: store, sources: [github], catalog: catalog, logger: logger).call(period)
    end.not_to(
      raise_error
    )
    expect(store.pending_candidates(period)).to be_empty
    expect(fetch_candidate('broken')).to include(status: 'failed', error: 'DistinctToStringError: boom')
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'Retryable candidates remain'
    )
    expect(logger.string).to include('[github] candidate "broken" failed: DistinctToStringError: boom')
  end

  it 'retries failed candidates once before failing the run' do
    github.candidates = { 'Poland' => [{ source_id: 500, login: 'broken' }] }
    github.profiles = { 'broken' => profile(500, 'broken', 'Krakow, Poland') }
    github.repositories = { 'broken' => [repository(600, 'broken/tool', 5)] }
    attempts = 0
    allow(github).to receive(:user).and_wrap_original do |original, *args|
      attempts += 1
      raise Net::OpenTimeout, 'execution expired' if attempts == 1

      original.call(*args)
    end

    described_class.new(store: store, sources: [github], catalog: catalog, logger: StringIO.new).call(period)

    expect(fetch_candidate('broken')).to include(status: 'processed', error: nil)
    expect(fetch_repository_stats('broken/tool')).to include(owner_login: 'broken', stargazers_count: 5)
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'finished',
      error: nil
    )
    expect(attempts).to eq(2)
  end

  it 'continues processing later candidates after a retryable candidate crash' do
    github.candidates = {
      'Poland' => [{ source_id: 500, login: 'broken' }, { source_id: 1, login: 'alice' }]
    }
    github.fail_logins = ['broken']
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    logger = StringIO.new

    described_class.new(store: store, sources: [github], catalog: catalog, logger: logger).call(period)

    expect(logger.string).to include('[github] processing 2 candidates')
    expect(logger.string).to include('[github] candidate processing finished')
    expect(fetch_candidate('broken')).to include(status: 'failed')
    expect(fetch_candidate('alice')).to include(status: 'processed')
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'Retryable candidates remain'
    )
  end

  it 'marks a successfully processed unseen candidate with the source platform and login' do
    candidate = { platform: 'github', source_id: 1, login: 'alice' }
    fake_store = SinglePendingCandidateStore.new(candidate)
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    github.repositories = { 'alice' => [] }

    described_class.new(
      store: fake_store,
      sources: [github],
      catalog: double('catalog', search_terms: []),
      logger: StringIO.new
    ).call(period)

    expect(fake_store.marked_candidates).to include([period, 'github', 'alice', 'processed'])
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

  it 'processes a source without waiting for slower source discovery to finish' do
    started = Queue.new
    release = Queue.new
    slow_github = BlockingDiscoverySource.new('github', started, release)
    gitlab = FakeJobGitLab.new
    gitlab.candidates = { 'Poland' => [{ source_id: 2, login: 'bob' }] }
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 5)] }
    thread = Thread.new do
      described_class.new(store: store, sources: [slow_github, gitlab], catalog: catalog, logger: StringIO.new)
                     .call(period)
    end

    expect(started.pop).to eq('github')
    Timeout.timeout(2) do
      sleep 0.01 until fetch_candidate('bob', platform: 'gitlab')&.fetch(:status) == 'processed'
    end

    expect(fetch_repository_stats('bob/tool', platform: 'gitlab')).to include(owner_login: 'bob')
    release << true
    thread.value
  end

  it 'flushes job logs as they are written' do
    logger = FlushTrackingLogger.new

    described_class.new(store: store, sources: [github], catalog: catalog, logger: logger).call(period)

    expect(logger.lines).not_to be_empty
    expect(logger.flushes).to eq(logger.lines.length)
  end

  it 'accepts loggers without flush support' do
    expect do
      described_class.new(store: store, sources: [github], catalog: catalog, logger: NoFlushLogger.new).call(period)
    end.not_to raise_error
  end

  it 'serializes candidate discovery writes from parallel sources' do
    started = Queue.new
    release = Queue.new
    guarded_store = ConcurrentWriteDetectingStore.new(store)
    sources = [
      BlockingCandidateDiscoverySource.new('github', started, release, { source_id: 1, login: 'alice' }),
      BlockingCandidateDiscoverySource.new('gitlab', started, release, { source_id: 2, login: 'bob' })
    ]
    thread = Thread.new do
      described_class.new(store: guarded_store, sources: sources, catalog: catalog, logger: StringIO.new).call(period)
    end

    expect([started.pop, started.pop].sort).to eq(%w[github gitlab])
    2.times { release << true }
    thread.value

    expect(guarded_store.concurrent_write).to be(false)
  end

  it 'serializes candidate processing writes from parallel sources' do
    run_id = store.create_run(period)
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, platform: 'gitlab', source_id: 2, login: 'bob', source_query: 'Poland')
    guarded_store = ConcurrentWriteDetectingStore.new(store)
    gitlab = FakeJobGitLab.new
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    github.repositories = { 'alice' => [repository(10, 'alice/app', 5)] }
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }

    described_class.new(
      store: guarded_store,
      sources: [github, gitlab],
      catalog: catalog,
      logger: StringIO.new
    ).call(period)

    expect(store.pending_candidates(period)).to be_empty
    expect(fetch_row('SELECT status FROM sync_runs WHERE id = ?', [run_id])).to include(status: 'finished')
    expect(guarded_store.concurrent_write).to be(false)
  end

  it 'serializes already processed candidate writes from parallel sources' do
    store.create_run(period)
    upsert_user(user_attributes(1, 'alice').merge(platform: 'github'))
    record_user_stats(user_stats(1, 'alice').merge(platform: 'github'))
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland')
    store.record_candidate(period, platform: 'gitlab', source_id: 2, login: 'bob', source_query: 'Poland')
    guarded_store = ConcurrentWriteDetectingStore.new(store)
    gitlab = FakeJobGitLab.new
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }

    described_class.new(
      store: guarded_store,
      sources: [github, gitlab],
      catalog: catalog,
      logger: StringIO.new
    ).call(period)

    expect(fetch_candidate('alice')).to include(status: 'processed', error: nil)
    expect(fetch_candidate('bob', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect(guarded_store.concurrent_write).to be(false)
  end

  it 'serializes missing candidate writes from parallel sources' do
    store.create_run(period)
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'missing', source_query: 'Poland')
    store.record_candidate(period, platform: 'gitlab', source_id: 2, login: 'bob', source_query: 'Poland')
    guarded_store = ConcurrentWriteDetectingStore.new(store)
    gitlab = FakeJobGitLab.new
    github.missing_logins = ['missing']
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }

    described_class.new(
      store: guarded_store,
      sources: [github, gitlab],
      catalog: catalog,
      logger: StringIO.new
    ).call(period)

    expect(fetch_candidate('missing')).to include(status: 'missing', error: nil)
    expect(fetch_candidate('bob', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect(guarded_store.concurrent_write).to be(false)
  end

  it 'serializes rejected candidate writes from parallel sources' do
    store.create_run(period)
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'outsider', source_query: 'Poland')
    store.record_candidate(period, platform: 'gitlab', source_id: 2, login: 'bob', source_query: 'Poland')
    guarded_store = ConcurrentWriteDetectingStore.new(store)
    gitlab = FakeJobGitLab.new
    github.profiles = { 'outsider' => profile(1, 'outsider', 'Berlin, Germany') }
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }

    described_class.new(
      store: guarded_store,
      sources: [github, gitlab],
      catalog: catalog,
      logger: StringIO.new
    ).call(period)

    expect(fetch_candidate('outsider')).to include(status: 'rejected', error: nil)
    expect(fetch_candidate('bob', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect(guarded_store.concurrent_write).to be(false)
  end

  it 'logs processing source failures with the process stage' do
    store.create_run(period)
    store.record_candidate(period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland')
    logger = StringIO.new

    expect do
      described_class.new(
        store: FailingPendingCandidatesStore.new(store),
        sources: [github],
        catalog: catalog,
        logger: logger
      ).call(period)
    end.to raise_error(RuntimeError, 'pending failed')

    expect(logger.string).to include('[github] process failed: RuntimeError: pending failed')
  end

  it 'continues when only one parallel source fails' do
    logger = StringIO.new
    healthy_source = FakeJobGitLab.new
    healthy_source.candidates = { 'Poland' => [] }
    failing_source = FailingDiscoverySource.new('github', error: DistinctToStringError.new('discovery failed'))
    sources = [failing_source, healthy_source]

    described_class.new(store: store, sources: sources, catalog: catalog, logger: logger).call(period)

    expect(logger.string).to include('[github] discover failed: DistinctToStringError: discovery failed')
    expect(logger.string).to include('[gitlab] candidate discovery finished')
  end

  it 'fails the run when every source fails before processing can continue' do
    sources = [
      FailingDiscoverySource.new('github', error: DistinctToStringError.new('discovery failed')),
      FailingDiscoverySource.new('gitlab', error: DistinctToStringError.new('discovery failed'))
    ]

    expect do
      described_class.new(store: store, sources: sources, catalog: catalog, logger: StringIO.new).call(period)
    end.to raise_error(DistinctToStringError)
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'DistinctToStringError: discovery failed'
    )
  end

  it 'does not record run failure when the run cannot be created' do
    failing_store = FailingCreateRunStore.new

    expect do
      described_class.new(store: failing_store, sources: [github], catalog: catalog, logger: StringIO.new).call(period)
    end.to raise_error(RuntimeError, 'database unavailable')
  end

  it 'marks the run as failed when the process is interrupted' do
    allow(store).to receive(:retryable_candidates?).and_raise(
      PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted,
      'Received SIGTERM'
    )

    expect { job.call(period) }.to raise_error(
      PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted,
      'Received SIGTERM'
    )
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted: Received SIGTERM'
    )
  end

  it 'stops source worker threads before recording an interrupted run failure' do
    interrupted_error = PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted
    thread = JoinInterruptedThread.new(interrupted_error.new('Received SIGTERM'))
    allow(Thread).to receive(:new).and_return(thread)

    expect do
      described_class.new(store: store, sources: [github], catalog: catalog, logger: StringIO.new).call(period)
    end.to raise_error(interrupted_error, 'Received SIGTERM')

    expect(thread).to be_killed
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted: Received SIGTERM'
    )
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

  def repository(id, full_name, stars, homepage: 'https://repo.example', fork: false, archived: false)
    {
      source_id: id,
      name: full_name.split('/').last,
      full_name: full_name,
      description: "Repository #{full_name}",
      html_url: "https://github.com/#{full_name}",
      homepage: homepage,
      language: 'Ruby',
      fork: fork,
      archived: archived,
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

  def optional_profile
    {
      source_id: 3,
      login: 'optional',
      location: 'Warsaw, Poland',
      html_url: 'https://github.com/optional'
    }
  end

  def optional_repository
    {
      source_id: 30,
      name: 'tool',
      full_name: 'optional/tool',
      html_url: 'https://github.com/optional/tool',
      fork: false,
      archived: false,
      stars: 5
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

  def repository_attributes(id, full_name)
    {
      github_id: id,
      owner_github_id: 1,
      owner_login: 'alice',
      name: full_name.split('/').last,
      full_name: full_name,
      description: "Repository #{full_name}",
      html_url: "https://github.com/#{full_name}",
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false
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
      merged_pull_requests_count: 0
    }
  end

  def job
    described_class.new(store: store, sources: [github], catalog: catalog, logger: StringIO.new)
  end

  def upsert_user(attributes)
    snapshot_repository.upsert_user(attributes)
  end

  def record_user_stats(attributes)
    snapshot_repository.record_user_stats(attributes)
  end

  def upsert_repository(attributes)
    snapshot_repository.upsert_repository(attributes)
  end

  def record_repository_stats(attributes)
    snapshot_repository.record_repository_stats(attributes)
  end

  def user_rankings(scope, period_start: period.start_date.to_s)
    ranking_read_model.user_rankings(scope, period_start: period_start)
  end

  def repository_rankings(scope, period_start: period.start_date.to_s)
    ranking_read_model.repository_rankings(scope, period_start: period_start)
  end

  def run_job_with(source:)
    described_class.new(
      store: store,
      sources: [source],
      catalog: catalog,
      logger: StringIO.new
    ).call(period)
  end

  def organization_rankings(period_start: period.start_date.to_s)
    ranking_read_model.organization_rankings(period_start: period_start)
  end

  def organization_repository_rankings(period_start: period.start_date.to_s)
    ranking_read_model.organization_repository_rankings(period_start: period_start)
  end

  def seed_alice_and_bob_discovery
    github.candidates = {
      'Poland' => [{ source_id: 1, login: 'alice' }, { source_id: 2, login: 'bob' }]
    }
    github.profiles = {
      'alice' => profile(1, 'alice', 'Krakow, Poland', blog: ''),
      'bob' => profile(2, 'bob', 'Berlin, Germany')
    }
    github.repositories = {
      'alice' => [
        repository(10, 'alice/app', 12),
        repository(11, 'alice/lib', 5, homepage: '', fork: true, archived: true)
      ]
    }
  end

  def seed_previous_repository_observation(previous_period)
    upsert_user(user_attributes(1, 'alice'))
    upsert_repository(repository_attributes(10, 'alice/app'))
    record_repository_stats(
      period_start: previous_period.start_date.to_s,
      repository_github_id: 10,
      owner_github_id: 1,
      owner_login: 'alice',
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: 10,
      monthly_stars_delta: 0
    )
  end

  def organization_snapshot_record(period)
    PolishOpenSourceRank::Contexts::Ranking::Domain::OrganizationSnapshot.new(
      period: period,
      platform: 'github',
      source_id: 9,
      login: 'polish-org',
      name: 'Polish Org',
      location_raw: 'Warsaw, Poland',
      city: 'Warszawa',
      country: 'Poland',
      email: 'org@example.com',
      homepage: nil,
      html_url: 'https://github.com/polish-org',
      avatar_url: nil,
      public_repository_count: 0,
      total_stars: 0,
      monthly_stars_delta: 0,
      members_count: 0
    )
  end

  def expect_finished_run
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'finished',
      error: nil
    )
  end

  def expect_persisted_alice_repositories
    expect(fetch_repository('alice/app')).to include(
      description: 'Repository alice/app',
      homepage: 'https://repo.example',
      language: 'Ruby',
      fork: 0,
      archived: 0
    )
    expect(fetch_repository('alice/lib')).to include(homepage: nil, fork: 1, archived: 1)
  end

  def expect_persisted_alice_repository_stats
    expect(fetch_repository_stats('alice/app')).to include(
      period_start: '2026-04-01',
      platform: 'github',
      repository_github_id: 10,
      owner_github_id: 1,
      owner_login: 'alice',
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: 12,
      monthly_stars_delta: 3
    )
  end

  def expect_persisted_alice_profile
    expect(fetch_user('alice')).to include(
      platform: 'github',
      github_id: 1,
      login: 'alice',
      name: 'Alice',
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: 'alice@example.com',
      homepage: nil,
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example/alice.png'
    )
  end

  def expect_persisted_alice_stats
    expect(fetch_user_stats('alice')).to include(
      period_start: '2026-04-01',
      platform: 'github',
      user_github_id: 1,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 2,
      total_stars: 17,
      monthly_stars_delta: 4,
      merged_pull_requests_count: 0
    )
  end

  def fetch_user(login, platform: 'github', table: 'users')
    fetch_row(<<~SQL, [platform, login])
      SELECT platform, github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url
      FROM #{table}
      WHERE platform = ? AND login = ?
    SQL
  end

  def fetch_user_stats(login, platform: 'github')
    fetch_row(<<~SQL, [platform, login])
      SELECT period_start, platform, user_github_id, login, city, country, public_repo_count, total_stars,
             monthly_stars_delta, merged_pull_requests_count
      FROM user_monthly_stats
      WHERE platform = ? AND login = ?
    SQL
  end

  def fetch_organization_stats(login, platform: 'github')
    fetch_row(<<~SQL, [platform, login])
      SELECT period_start, platform, organization_github_id, login, city, country, public_repo_count, total_stars,
             monthly_stars_delta, members_count
      FROM organization_monthly_stats
      WHERE platform = ? AND login = ?
    SQL
  end

  def fetch_candidate(login, platform: 'github', table: 'candidate_users')
    fetch_row(
      "SELECT platform, login, status, error FROM #{table} WHERE platform = ? AND login = ?",
      [platform, login]
    )
  end

  def fetch_repository(full_name, platform: 'github')
    fetch_row(<<~SQL, [platform, full_name])
      SELECT platform, full_name, description, homepage, language, fork, archived
      FROM repositories
      WHERE platform = ? AND full_name = ?
    SQL
  end

  def fetch_repository_stats(full_name, platform: 'github', period_start: period.start_date.to_s)
    fetch_row(<<~SQL, [period_start, platform, full_name])
      SELECT stats.period_start, stats.platform, stats.repository_github_id, stats.owner_github_id,
             stats.owner_login, stats.owner_city, stats.owner_country, stats.stargazers_count,
             stats.monthly_stars_delta
      FROM repository_monthly_stats stats
      INNER JOIN repositories ON repositories.platform = stats.platform
       AND repositories.github_id = stats.repository_github_id
      WHERE stats.period_start = ? AND stats.platform = ? AND repositories.full_name = ?
    SQL
  end

  def fetch_row(sql, params = [])
    database.fetch_all(sql, params).first
  end

  def database
    @database ||= PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path).tap do |db|
      PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
        db,
        PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
      ).bootstrap!
    end
  end

  def run_repository
    @run_repository ||= PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository.new(
      database
    )
  end

  def candidate_queue
    @candidate_queue ||= PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue.new(
      database
    )
  end

  def snapshot_repository
    @snapshot_repository ||= PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository.new(
      database
    )
  end

  def ranking_retention
    @ranking_retention ||= PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention.new(
      database
    )
  end

  def ranking_read_model
    @ranking_read_model ||= PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel.new(
      database
    )
  end
end

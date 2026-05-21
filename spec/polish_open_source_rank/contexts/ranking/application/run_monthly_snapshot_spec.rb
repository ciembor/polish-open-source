# frozen_string_literal: true

require 'timeout'

class FakeJobGitHub
  attr_accessor :activities, :candidates, :deltas, :fail_errors, :fail_logins, :missing_logins, :profiles,
                :repositories
  attr_reader :activity_periods, :delta_periods, :searched_terms, :user_calls

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
    @searched_terms = []
    @user_calls = []
  end

  def search_users_by_location(term)
    searched_terms << term
    candidates.fetch(term, [])
  end

  def platform
    'github'
  end

  def user(login, id = nil)
    user_calls << [login, id]
    raise fail_errors.fetch(login) if fail_errors.key?(login)
    raise 'boom' if fail_logins.include?(login)
    raise missing_error if missing_logins.include?(login)

    profiles.fetch(login)
  end

  def repositories_for(profile)
    repositories.fetch(profile.fetch(:login), [])
  end

  def repository_stars_delta(repository, period)
    delta_periods << [repository.fetch(:full_name), period]
    deltas.fetch(repository.fetch(:full_name), 0)
  end

  def public_activity_count(profile, period)
    activity_periods << [profile.fetch(:login), period]
    activities.fetch(profile.fetch(:login), 0)
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
  let(:path) { File.join(Dir.mktmpdir, 'job.sqlite3') }
  let(:store) { PolishOpenSourceRank::Infrastructure::SQLiteStore.new(path).migrate! }
  let(:catalog) { double('catalog', search_terms: ['Poland']) }
  let(:github) { FakeJobGitHub.new }

  it 'discovers candidates, rejects non-Polish profiles, and stores Polish snapshots' do
    seed_alice_and_bob_discovery
    github.deltas = { 'alice/app' => 3, 'alice/lib' => 1 }
    github.activities = { 'alice' => 7 }
    allow(store).to receive(:prune_rankings).and_call_original

    job.call(period)

    expect(store).to have_received(:prune_rankings).with(period)
    expect(store.user_rankings('poland').fetch(:trending).first).to include(login: 'alice', monthly_stars_delta: 4)
    expect(store.user_rankings('krakow').fetch(:active).first).to include(public_activity_count: 7)
    expect(store.repository_rankings('poland').fetch(:top).map do |row|
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
    expect(github.activity_periods).to eq([['alice', period]])
  end

  it 'uses previous repository observations and skips empty repositories when calculating star deltas' do
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
    expect(fetch_repository_stats('alice/empty')).to include(monthly_stars_delta: 0)
    expect(github.delta_periods).to eq([['alice/new', period]])
  end

  it 'marks an already snapshotted pending candidate as processed' do
    store.upsert_user(user_attributes(1, 'alice'))
    store.record_user_stats(user_stats(1, 'alice'))
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

  it 'checks already snapshotted candidates within their source platform' do
    gitlab = FakeJobGitLab.new
    store.upsert_user(user_attributes(1, 'alice').merge(platform: 'github'))
    store.record_user_stats(user_stats(1, 'alice').merge(platform: 'github'))
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')
    gitlab.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    gitlab.repositories = { 'alice' => [] }

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(gitlab.user_calls).to eq([['alice', 1]])
    expect(fetch_candidate('alice', platform: 'gitlab')).to include(status: 'processed', error: nil)
  end

  it 'marks already snapshotted candidates on their source platform' do
    gitlab = FakeJobGitLab.new
    store.upsert_user(user_attributes(1, 'alice').merge(platform: 'gitlab'))
    store.record_user_stats(user_stats(1, 'alice').merge(platform: 'gitlab'))
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')

    described_class.new(store: store, sources: [gitlab], catalog: catalog, logger: StringIO.new).call(period)

    expect(gitlab.user_calls).to be_empty
    expect(fetch_candidate('alice', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect_finished_run
  end

  it 'reprocesses already snapshotted candidates during an explicit refresh' do
    gitlab = FakeJobGitLab.new
    store.record_candidate(period, platform: 'gitlab', source_id: 1, login: 'alice', source_query: 'Poland')
    store.upsert_user(user_attributes(1, 'alice').merge(platform: 'gitlab'))
    store.record_user_stats(user_stats(1, 'alice').merge(platform: 'gitlab'))
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
      described_class.new(store: store, github: github).call(period)
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
    store.upsert_user(user_attributes(2, 'bob').merge(platform: 'gitlab'))
    store.record_user_stats(user_stats(2, 'bob').merge(platform: 'gitlab', public_repo_count: 1, total_stars: 4))
    store.mark_candidate(period, 'gitlab', 'bob', 'processed')
    store.finish_run(run_id)
    gitlab = FakeJobGitLab.new
    gitlab.profiles = { 'bob' => profile(2, 'bob', 'Warsaw, Poland') }
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }

    described_class.new(
      store: store,
      sources: [gitlab],
      catalog: double('catalog', search_terms: []),
      logger: StringIO.new
    ).call(period)

    expect(fetch_candidate('bob', platform: 'gitlab')).to include(status: 'processed', error: nil)
    expect(fetch_repository_stats('bob/tool', platform: 'gitlab')).to include(
      owner_login: 'bob',
      stargazers_count: 4
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

    expect { described_class.new(store: store, github: github, catalog: catalog, logger: logger).call(period) }.not_to(
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

  it 'continues processing later candidates after a retryable candidate crash' do
    github.candidates = {
      'Poland' => [{ source_id: 500, login: 'broken' }, { source_id: 1, login: 'alice' }]
    }
    github.fail_logins = ['broken']
    github.profiles = { 'alice' => profile(1, 'alice', 'Krakow, Poland') }
    logger = StringIO.new

    described_class.new(store: store, github: github, catalog: catalog, logger: logger).call(period)

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
      github: github,
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
    gitlab.repositories = { 'bob' => [repository(20, 'bob/tool', 4)] }
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

    described_class.new(store: store, github: github, catalog: catalog, logger: logger).call(period)

    expect(logger.lines).not_to be_empty
    expect(logger.flushes).to eq(logger.lines.length)
  end

  it 'accepts loggers without flush support' do
    expect do
      described_class.new(store: store, github: github, catalog: catalog, logger: NoFlushLogger.new).call(period)
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
    store.upsert_user(user_attributes(1, 'alice').merge(platform: 'github'))
    store.record_user_stats(user_stats(1, 'alice').merge(platform: 'github'))
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
      PolishOpenSourceRank::Application::MonthlySnapshotInterrupted,
      'Received SIGTERM'
    )

    expect { job.call(period) }.to raise_error(
      PolishOpenSourceRank::Application::MonthlySnapshotInterrupted,
      'Received SIGTERM'
    )
    expect(fetch_row('SELECT status, error FROM sync_runs WHERE period_start = ?', ['2026-04-01'])).to include(
      status: 'failed',
      error: 'PolishOpenSourceRank::Application::MonthlySnapshotInterrupted: Received SIGTERM'
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
      stars: 1
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
      public_activity_count: 0
    }
  end

  def job
    described_class.new(store: store, github: github, catalog: catalog, logger: StringIO.new)
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
    store.upsert_user(user_attributes(1, 'alice'))
    store.upsert_repository(repository_attributes(10, 'alice/app'))
    store.record_repository_stats(
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
      public_activity_count: 7
    )
  end

  def fetch_user(login, platform: 'github')
    fetch_row(<<~SQL, [platform, login])
      SELECT platform, github_id, login, name, location_raw, city, country, email, homepage, html_url, avatar_url
      FROM users
      WHERE platform = ? AND login = ?
    SQL
  end

  def fetch_user_stats(login, platform: 'github')
    fetch_row(<<~SQL, [platform, login])
      SELECT period_start, platform, user_github_id, login, city, country, public_repo_count, total_stars,
             monthly_stars_delta, public_activity_count
      FROM user_monthly_stats
      WHERE platform = ? AND login = ?
    SQL
  end

  def fetch_candidate(login, platform: 'github')
    fetch_row(
      'SELECT platform, login, status, error FROM candidate_users WHERE platform = ? AND login = ?',
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
    row = database.execute(sql, params).first
    row.each_with_object({}) do |(key, value), result|
      result[key.to_sym] = value unless key.is_a?(Integer)
    end
  end

  def database
    @database ||= SQLite3::Database.new(path).tap do |connection|
      connection.results_as_hash = true
    end
  end
end

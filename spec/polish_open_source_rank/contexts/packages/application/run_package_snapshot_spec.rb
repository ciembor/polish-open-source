# frozen_string_literal: true

class FakePackageRunRepository
  attr_reader :failed, :finished

  def create(_period, ecosystem:, refresh:)
    @ecosystem = ecosystem
    @refresh = refresh
    123
  end

  def finish(run_id)
    @finished = run_id
  end

  def fail(run_id, error)
    @failed = { run_id: run_id, error: error }
  end
end

class FakeRegistryPackageRepository
  attr_reader :recorded, :resolved

  def initialize(packages)
    @packages = packages
    @recorded = []
    @resolved = []
  end

  def resolve_from_manifests(period, ecosystem:, limit:)
    resolved << { period: period, ecosystem: ecosystem, limit: limit }
  end

  def packages_to_fetch(_period, ecosystem:, limit:, refresh:)
    @packages.select { |package| ecosystem.nil? || package.fetch(:ecosystem) == ecosystem }.first(limit).tap do
      @fetch_options = { refresh: refresh }
    end
  end

  def record_fetch_result(period, package, result)
    recorded << { period: period, package: package, result: result }
  end
end

class FakePackageRegistryClient
  def initialize(failures: {})
    @failures = failures.transform_values(&:dup)
  end

  def fetch(package_name)
    raise 'registry timeout' if @failures.fetch(package_name, []).shift

    PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(
      status: 'ok',
      package: PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage.new(
        ecosystem: 'npm',
        package_name: package_name,
        registry_url: "https://www.npmjs.com/package/#{package_name}"
      ),
      snapshot: PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageSnapshot.new(
        ecosystem: 'npm',
        package_name: package_name,
        downloads_30d: 5
      )
    )
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Application::RunPackageSnapshot do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:registry_client_failures) { {} }

  it 'runs the package snapshot flow and records per-package fetch failures without aborting' do
    allow(self).to receive(:registry_client_failures).and_return({ 'broken' => [true] })

    result = use_case.call(
      period,
      ecosystem: 'npm',
      limits: { repository: 100, scan: 20, manifest: 30, registry: 10 },
      refresh: true
    )

    expect(repository_queue).to have_received(:reset_stale_processing).with(period).twice
    expect(repository_queue).to have_received(:enqueue).with(period, limit: 100).twice
    expect(manifest_scanner).to have_received(:call).with(period, ecosystem: 'npm', limit: 20, refresh: true).twice
    expect(registry_packages.resolved).to eq(
      [
        { period: period, ecosystem: 'npm', limit: 30 },
        { period: period, ecosystem: 'npm', limit: 30 }
      ]
    )
    expect(registry_packages.recorded.map { |record| record.fetch(:result).status }).to eq(%w[ok failed ok ok])
    expect(run_repository.finished).to eq(123)
    expect(run_repository.failed).to be_nil
    expect(result).to include(
      stale_scans_reset: 0,
      scanned: 2,
      failed: 0,
      manifests: 4,
      registry_fetched: 4,
      registry_ok: 3,
      registry_failed: 0,
      snapshots_written: 3,
      retry_passes: 1
    )
  end

  it 'retries package stages once when a transient registry fetch fails' do
    allow(self).to receive(:registry_client_failures).and_return({ 'broken' => [true] })

    use_case.call(period, ecosystem: 'npm', limit: 10, refresh: false)

    expect(repository_queue).to have_received(:reset_stale_processing).with(period).twice
    expect(repository_queue).to have_received(:enqueue).with(period, limit: 10).twice
    expect(manifest_scanner).to have_received(:call).with(period, ecosystem: 'npm', limit: 10, refresh: false).twice
    expect(registry_packages.resolved).to eq(
      [
        { period: period, ecosystem: 'npm', limit: 10 },
        { period: period, ecosystem: 'npm', limit: 10 }
      ]
    )
  end

  it 'keeps --limit as a backwards-compatible shorthand for all stages' do
    use_case.call(period, ecosystem: 'npm', limit: 10, refresh: false)

    expect(repository_queue).to have_received(:enqueue).with(period, limit: 10)
    expect(manifest_scanner).to have_received(:call).with(period, ecosystem: 'npm', limit: 10, refresh: false)
    expect(registry_packages.resolved).to eq([{ period: period, ecosystem: 'npm', limit: 10 }])
  end

  it 'uses production defaults above the MVP sample size' do
    use_case.call(period, ecosystem: 'npm', refresh: false)

    expect(repository_queue).to have_received(:enqueue).with(period, limit: 5_000)
    expect(manifest_scanner).to have_received(:call).with(period, ecosystem: 'npm', limit: 5_000, refresh: false)
    expect(registry_packages.resolved).to eq([{ period: period, ecosystem: 'npm', limit: 10_000 }])
  end

  it 'marks the run failed and reraises store errors' do
    allow(repository_queue).to receive(:enqueue).and_raise(RuntimeError, 'schema is missing')

    expect do
      use_case.call(period, ecosystem: nil, limit: 10, refresh: false)
    end.to raise_error(RuntimeError)

    expect(run_repository.failed).to include(run_id: 123, error: 'RuntimeError: schema is missing')
  end

  def use_case
    described_class.new(
      run_repository: run_repository,
      repository_queue: repository_queue,
      manifest_scanner: manifest_scanner,
      registry_packages: registry_packages,
      registry_clients: registry_clients
    )
  end

  def registry_clients
    { 'npm' => FakePackageRegistryClient.new(failures: registry_client_failures) }
  end

  def run_repository
    @run_repository ||= FakePackageRunRepository.new
  end

  def repository_queue
    @repository_queue ||= double('package repository queue', reset_stale_processing: 0, enqueue: nil)
  end

  def manifest_scanner
    @manifest_scanner ||= double('manifest scanner', call: { scanned: 1, failed: 0, manifests: 2 })
  end

  def registry_packages
    @registry_packages ||= FakeRegistryPackageRepository.new(
      [
        { ecosystem: 'npm', package_name: 'ok', normalized_package_name: 'ok' },
        { ecosystem: 'npm', package_name: 'broken', normalized_package_name: 'broken' }
      ]
    )
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::CLI::PackageRankingsCommand do
  let(:output) { StringIO.new }
  let(:heartbeat) { instance_double(PolishOpenSourceRank::Contexts::Operations::Application::ProgressHeartbeat) }
  let(:job) do
    double(
      'package snapshot job',
      call: { scanned: 1, failed: 0, registry_fetched: 2, registry_ok: 1, registry_failed: 1 }
    )
  end
  let(:crawl_jobs) { double('crawl jobs', start: 7, finish: nil, fail: nil) }

  it 'runs a tracked package ranking job with period, ecosystem, limit, and refresh arguments' do
    described_class.call(
      %w[--period 2026-04 --ecosystem npm --limit 25 --refresh],
      job: job,
      output: output,
      crawl_jobs: crawl_jobs
    )

    expect(job).to have_received(:call).with(
      PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04'),
      ecosystem: 'npm',
      limits: { repository: 25, scan: 25, manifest: 25, registry: 25 },
      refresh: true
    )
    expect(crawl_jobs).to have_received(:start).with(
      command: 'package_rankings',
      arguments: %w[--period 2026-04 --ecosystem npm --limit 25 --refresh]
    )
    expect(crawl_jobs).to have_received(:finish).with(7)
    expect(output.string).to include('Package crawl summary:')
    expect(output.string).to include('registry_fetched=2')
    expect(output.string).to include('Finished package ranking run for 2026-04')
  end

  it 'passes stage-specific package crawl limits' do
    described_class.call(
      %w[--period 2026-04 --repository-limit 200 --scan-limit 150 --manifest-limit 300 --registry-limit 250],
      job: job,
      output: output
    )

    expect(job).to have_received(:call).with(
      PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04'),
      ecosystem: nil,
      limits: { repository: 200, scan: 150, manifest: 300, registry: 250 },
      refresh: false
    )
  end

  it 'passes all as an unbounded package crawl limit' do
    described_class.call(
      %w[--period 2026-04 --limit all],
      job: job,
      output: output
    )

    expect(job).to have_received(:call).with(
      PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04'),
      ecosystem: nil,
      limits: { repository: 'all', scan: 'all', manifest: 'all', registry: 'all' },
      refresh: false
    )
  end

  it 'does not run package rankings before monthly rankings finish for the period' do
    monthly_completion =
      instance_double(
        PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteMonthlySnapshotCompletion,
        complete?: false
      )

    expect do
      described_class.call(
        %w[--period 2026-04 --require-monthly-complete],
        job: job,
        output: output,
        monthly_completion: monthly_completion
      )
    end.to raise_error(described_class::MonthlySnapshotIncomplete, 'Monthly rankings are not complete for 2026-04')

    expect(monthly_completion).to have_received(:complete?).with(
      PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    )
    expect(job).not_to have_received(:call)
  end

  it 'runs package rankings after monthly rankings finish for the period' do
    monthly_completion =
      instance_double(
        PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteMonthlySnapshotCompletion,
        complete?: true
      )

    described_class.call(
      %w[--period 2026-04 --require-monthly-complete],
      job: job,
      output: output,
      monthly_completion: monthly_completion
    )

    expect(job).to have_received(:call)
  end

  it 'prints help with supported ecosystems' do
    described_class.call(%w[--help], job: job, output: output)

    expect(output.string).to include('--repository-limit N')
    expect(output.string).to include(
      'Supported ecosystems: npm, rubygems, crates, pypi, hex, packagist, go, homebrew, nuget, maven'
    )
    expect(job).not_to have_received(:call)
  end

  it 'marks tracked jobs as failed when the job raises' do
    allow(job).to receive(:call).and_raise(ArgumentError, 'Unsupported package ecosystem: unknown')

    expect do
      described_class.call(%w[--period 2026-04 --ecosystem unknown], job: job, output: output, crawl_jobs: crawl_jobs)
    end.to raise_error(ArgumentError)

    expect(crawl_jobs).to have_received(:fail).with(
      7,
      'ArgumentError: Unsupported package ecosystem: unknown'
    )
  end

  it 'retries transient package job failures once before marking the job failed' do
    attempts = 0
    allow(job).to receive(:call) do
      attempts += 1
      raise Net::OpenTimeout, 'execution expired' if attempts == 1

      { scanned: 1, failed: 0, registry_fetched: 1, registry_ok: 1, registry_failed: 0 }
    end
    allow(crawl_jobs).to receive(:retry)

    described_class.call(%w[--period 2026-04], job: job, output: output, crawl_jobs: crawl_jobs)

    expect(crawl_jobs).to have_received(:retry).with(7, 'Net::OpenTimeout: execution expired')
    expect(crawl_jobs).to have_received(:finish).with(7)
    expect(crawl_jobs).not_to have_received(:fail)
    expect(job).to have_received(:call).twice
  end

  it 'marks process stop signals as interrupted' do
    term_handler = nil
    previous_handlers = []
    allow(Signal).to receive(:trap).and_wrap_original do |original, signal, handler = nil, &block|
      if block
        term_handler = block if signal == 'TERM'
        previous_handlers << signal
        'DEFAULT'
      else
        original.call(signal, handler)
      end
    end
    allow(job).to receive(:call) { term_handler.call }

    interrupted_error = PolishOpenSourceRank::Contexts::Operations::Application::PackageSnapshotInterrupted

    expect do
      described_class.call(%w[--period 2026-04], job: job, output: output, crawl_jobs: crawl_jobs)
    end.to raise_error(interrupted_error, 'Received SIGTERM')

    expect(crawl_jobs).to have_received(:fail).with(7, 'Received SIGTERM', status: 'interrupted')
    expect(crawl_jobs).not_to have_received(:finish)
    expect(Signal).to have_received(:trap).with('INT', 'DEFAULT')
    expect(Signal).to have_received(:trap).with('TERM', 'DEFAULT')
    expect(previous_handlers).to eq(%w[INT TERM])
  end

  it 'wraps the package job in a stall watchdog when a heartbeat is configured' do
    watchdog = instance_double(PolishOpenSourceRank::Contexts::Operations::Application::StalledCrawlWatchdog)
    allow(watchdog).to receive(:call).and_yield
    watchdog_class = class_double(PolishOpenSourceRank::Contexts::Operations::Application::StalledCrawlWatchdog)
    allow(watchdog_class).to receive(:new).and_return(watchdog)

    described_class.new(
      argv: %w[--period 2026-04],
      job: job,
      output: output,
      crawl_jobs: crawl_jobs,
      watchdog: {
        heartbeat: heartbeat,
        watchdog_class: watchdog_class
      }
    ).call

    expect(watchdog_class).to have_received(:new).with(
      heartbeat: heartbeat,
      output: output,
      label: 'Package crawl',
      timeout_seconds: described_class::DEFAULT_STALE_TIMEOUT_SECONDS
    )
    expect(watchdog).to have_received(:call)
  end
end

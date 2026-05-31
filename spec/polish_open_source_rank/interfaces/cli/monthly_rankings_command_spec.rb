# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::CLI::MonthlyRankingsCommand do
  it 'runs a monthly job with injected persistence and sources' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04'], job: job, output: output)

    expect_default_monthly_call(job)
    expect(output.string).to include('Finished monthly ranking run for 2026-04')
  end

  it 'passes explicit refresh requests to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--refresh'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: true,
      use_snapshot_star_diff: false
    )
  end

  it 'keeps source star history enabled for explicit star recalculation requests' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--refresh', '--recalculate-stars'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: true,
      use_snapshot_star_diff: false
    )
  end

  it 'passes explicit star diff requests to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--use-stars-diff'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      use_snapshot_star_diff: true
    )
  end

  it 'passes an explicit scope to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--scope', 'organizations'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      use_snapshot_star_diff: false,
      scope: :organizations
    )
  end

  it 'passes existing-only repair requests to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(['--month', '2026-04', '--existing-only'], job: job, output: output)

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      use_snapshot_star_diff: false,
      existing_only: true
    )
  end

  it 'passes monthly metric backfill flags to the monthly job' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    allow(job).to receive(:call)

    described_class.call(
      [
        '--month', '2026-04',
        '--existing-only',
        '--refresh-user-merged-prs',
        '--refresh-organization-members',
        '--refresh-organization-merged-prs'
      ],
      job: job,
      output: output
    )

    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      use_snapshot_star_diff: false,
      existing_only: true,
      backfill: {
        refresh_user_merged_prs: true,
        refresh_organization_members: true,
        refresh_organization_merged_prs: true
      }
    )
  end

  it 'tracks crawl jobs through success, failure, and interruption boundaries' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      start: 17,
      finish: nil,
      fail: nil
    )
    allow(job).to receive(:call)

    described_class.call(
      ['--month', '2026-04', '--platform', 'github', '--scope', 'organizations'],
      job: job,
      output: output,
      crawl_jobs: crawl_jobs
    )

    expect(crawl_jobs).to have_received(:start).with(
      command: 'monthly_rankings',
      arguments: ['--month', '2026-04', '--platform', 'github', '--scope', 'organizations']
    )
    expect(crawl_jobs).to have_received(:finish).with(17)
    expect(crawl_jobs).not_to have_received(:fail)
  end

  it 'marks interrupted crawl jobs as interrupted' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      start: 19,
      finish: nil,
      fail: nil
    )
    allow(job).to receive(:call).and_raise(
      PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted,
      'Received SIGTERM'
    )

    interrupted_error = PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted

    expect do
      described_class.call(['--month', '2026-04'], job: job, output: output, crawl_jobs: crawl_jobs)
    end.to raise_error(interrupted_error, 'Received SIGTERM')

    expect(crawl_jobs).to have_received(:fail).with(19, 'Received SIGTERM', status: 'interrupted')
    expect(crawl_jobs).not_to have_received(:finish)
  end

  it 'retries transient crawl job failures once before marking the job failed' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      start: 29,
      retry: nil,
      finish: nil,
      fail: nil
    )
    attempts = 0
    allow(job).to receive(:call) do
      attempts += 1
      raise Net::OpenTimeout, 'execution expired' if attempts == 1
    end

    described_class.call(['--month', '2026-04'], job: job, output: output, crawl_jobs: crawl_jobs)

    expect(crawl_jobs).to have_received(:retry).with(29, 'Net::OpenTimeout: execution expired')
    expect(crawl_jobs).to have_received(:finish).with(29)
    expect(crawl_jobs).not_to have_received(:fail)
    expect(job).to have_received(:call).twice
  end

  it 'marks failed crawl jobs with the original error' do
    output = StringIO.new
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      start: 23,
      finish: nil,
      fail: nil
    )
    allow(job).to receive(:call).and_raise(RuntimeError, 'boom')

    expect do
      described_class.call(['--month', '2026-04'], job: job, output: output, crawl_jobs: crawl_jobs)
    end.to raise_error(RuntimeError, 'boom')

    expect(crawl_jobs).to have_received(:fail).with(23, 'RuntimeError: boom')
    expect(crawl_jobs).not_to have_received(:finish)
  end

  it 'turns process stop signals into job-visible interruptions' do
    output = StringIO.new
    term_handler = nil
    previous_handlers = []
    job = instance_double(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot)
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

    interrupted_error = PolishOpenSourceRank::Contexts::Operations::Application::MonthlySnapshotInterrupted

    expect do
      described_class.call(['--month', '2026-04'], job: job, output: output)
    end.to raise_error(interrupted_error, 'Received SIGTERM')

    expect_default_monthly_call(job)
    expect(output.string).to be_empty
    expect(Signal).to have_received(:trap).with('INT', 'DEFAULT')
    expect(Signal).to have_received(:trap).with('TERM', 'DEFAULT')
    expect(previous_handlers).to eq(%w[INT TERM])
  end

  def expect_default_monthly_call(job)
    expect(job).to have_received(:call).with(
      have_attributes(key: '2026-04'),
      refresh: false,
      use_snapshot_star_diff: false
    )
  end
end

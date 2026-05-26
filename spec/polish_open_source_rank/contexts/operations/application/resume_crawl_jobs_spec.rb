# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Application::ResumeCrawlJobs do
  it 'replays each interrupted monthly crawl with its tracked arguments' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [
        { id: 1, command: 'monthly_rankings', arguments: ['--month', '2026-04'] },
        { id: 2, command: 'package_rankings', arguments: ['--period', '2026-04', '--ecosystem', 'npm'] }
      ]
    )
    allow(crawl_jobs).to receive(:finish)
    monthly_runner = instance_double(Proc, call: nil)
    package_runner = instance_double(Proc, call: nil)

    described_class.new(crawl_jobs: crawl_jobs, monthly_runner: monthly_runner, package_runner: package_runner).call

    expect(monthly_runner).to have_received(:call).with(['--month', '2026-04']).ordered
    expect(package_runner).to have_received(:call).with(
      [
        '--period', '2026-04',
        '--ecosystem', 'npm',
        '--repository-limit', '1000',
        '--scan-limit', '1000',
        '--manifest-limit', '2000',
        '--registry-limit', '2000'
      ]
    ).ordered
    expect(crawl_jobs).to have_received(:finish).with(2)
  end

  it 'bounds resumed package crawl limits to production-safe batches' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [
        {
          id: 1,
          command: 'package_rankings',
          arguments: [
            '--period', '2026-04',
            '--ecosystem', 'npm',
            '--repository-limit', '5000',
            '--scan-limit', '5000',
            '--manifest-limit', '10000',
            '--registry-limit', '10000'
          ]
        }
      ]
    )
    allow(crawl_jobs).to receive(:finish)
    package_runner = instance_double(Proc, call: nil)

    described_class.new(
      crawl_jobs: crawl_jobs,
      monthly_runner: instance_double(Proc),
      package_runner: package_runner
    ).call

    expect(package_runner).to have_received(:call).with(
      [
        '--period', '2026-04',
        '--ecosystem', 'npm',
        '--repository-limit', '1000',
        '--scan-limit', '1000',
        '--manifest-limit', '2000',
        '--registry-limit', '2000'
      ]
    )
    expect(crawl_jobs).to have_received(:finish).with(1)
  end

  it 'adds package crawl limits when an interrupted run was recorded without explicit limits' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [{ id: 1, command: 'package_rankings', arguments: ['--period', '2026-04', '--ecosystem', 'npm'] }]
    )
    allow(crawl_jobs).to receive(:finish)
    package_runner = instance_double(Proc, call: nil)

    described_class.new(
      crawl_jobs: crawl_jobs,
      monthly_runner: instance_double(Proc),
      package_runner: package_runner
    ).call

    expect(package_runner).to have_received(:call).with(
      [
        '--period', '2026-04',
        '--ecosystem', 'npm',
        '--repository-limit', '1000',
        '--scan-limit', '1000',
        '--manifest-limit', '2000',
        '--registry-limit', '2000'
      ]
    )
    expect(crawl_jobs).to have_received(:finish).with(1)
  end

  it 'caps global package crawl limits before adding stage limits' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [{ id: 1, command: 'package_rankings', arguments: ['--period', '2026-04', '--limit', '5000'] }]
    )
    allow(crawl_jobs).to receive(:finish)
    package_runner = instance_double(Proc, call: nil)

    described_class.new(
      crawl_jobs: crawl_jobs,
      monthly_runner: instance_double(Proc),
      package_runner: package_runner
    ).call

    expect(package_runner).to have_received(:call).with(
      [
        '--period', '2026-04',
        '--limit', '1000',
        '--repository-limit', '1000',
        '--scan-limit', '1000',
        '--manifest-limit', '2000',
        '--registry-limit', '2000'
      ]
    )
    expect(crawl_jobs).to have_received(:finish).with(1)
  end

  it 'rejects unsupported resumable commands' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [{ command: 'unknown', arguments: [] }]
    )

    expect do
      described_class.new(crawl_jobs: crawl_jobs, monthly_runner: instance_double(Proc)).call
    end.to raise_error(ArgumentError, 'Unsupported resumable crawl command: unknown')
  end
end

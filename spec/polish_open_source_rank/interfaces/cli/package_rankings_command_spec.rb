# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::CLI::PackageRankingsCommand do
  let(:output) { StringIO.new }
  let(:job) { double('package snapshot job', call: nil) }
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
      limit: 25,
      refresh: true
    )
    expect(crawl_jobs).to have_received(:start).with(
      command: 'package_rankings',
      arguments: %w[--period 2026-04 --ecosystem npm --limit 25 --refresh]
    )
    expect(crawl_jobs).to have_received(:finish).with(7)
    expect(output.string).to include('Finished package ranking run for 2026-04')
  end

  it 'prints help with supported ecosystems' do
    described_class.call(%w[--help], job: job, output: output)

    expect(output.string).to include('Supported ecosystems: npm, rubygems, crates, pypi, hex, packagist, go')
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
end

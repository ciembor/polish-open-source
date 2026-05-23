# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::CLI::ResumeCrawlsCommand do
  it 'prints a no-op message when there is nothing to resume' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: []
    )
    output = StringIO.new
    command = described_class.new(job: instance_double(Object), crawl_jobs: crawl_jobs, output: output)

    command.call

    expect(output.string).to include('No interrupted crawl jobs to resume')
  end

  it 'lists and resumes interrupted crawls' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [
        { command: 'monthly_rankings', arguments: ['--month', '2026-04', '--scope', 'organizations'] },
        { command: 'package_rankings', arguments: ['--period', '2026-04', '--ecosystem', 'npm'] }
      ]
    )
    job = instance_double(PolishOpenSourceRank::Contexts::Operations::Application::ResumeCrawlJobs, call: nil)
    output = StringIO.new

    described_class.new(job: job, crawl_jobs: crawl_jobs, output: output).call

    expect(output.string).to include('Resuming monthly_rankings --month 2026-04 --scope organizations')
    expect(output.string).to include('Resuming package_rankings --period 2026-04 --ecosystem npm')
    expect(job).to have_received(:call)
  end
end

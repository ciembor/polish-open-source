# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Application::ResumeCrawlJobs do
  it 'replays each interrupted monthly crawl with its tracked arguments' do
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [
        { command: 'monthly_rankings', arguments: ['--month', '2026-04'] },
        { command: 'monthly_rankings', arguments: ['--month', '2026-04', '--scope', 'organizations'] }
      ]
    )
    monthly_runner = instance_double(Proc, call: nil)

    described_class.new(crawl_jobs: crawl_jobs, monthly_runner: monthly_runner).call

    expect(monthly_runner).to have_received(:call).with(['--month', '2026-04']).ordered
    expect(monthly_runner).to have_received(:call).with(
      ['--month', '2026-04', '--scope', 'organizations']
    ).ordered
  end
end

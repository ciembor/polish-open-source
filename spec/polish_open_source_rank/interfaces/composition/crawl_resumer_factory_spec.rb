# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::Composition::CrawlResumerFactory do
  it 'builds the crawl resumer command from configuration and infrastructure adapters' do
    configuration = instance_double(PolishOpenSourceRank::Configuration, database_path: 'db/test.sqlite3')
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    migration = instance_double(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration, bootstrap!: nil)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository
    )

    allow(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
      .to receive(:open).with('db/test.sqlite3').and_return(database)
    allow(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration)
      .to receive(:new)
      .with(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      .and_return(migration)
    allow(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to receive(:new).with(database).and_return(crawl_jobs)

    command = described_class.build(configuration: configuration, output: StringIO.new)

    expect(command).to be_a(PolishOpenSourceRank::Interfaces::CLI::ResumeCrawlsCommand)
    expect(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to have_received(:new).with(database)
  end

  it 'rebuilds interrupted monthly crawls through the ranking job factory' do
    configuration, crawl_jobs = stub_resume_environment
    monthly_command = instance_double(PolishOpenSourceRank::Interfaces::CLI::MonthlyRankingsCommand, call: nil)
    output = StringIO.new
    allow(PolishOpenSourceRank::Interfaces::Composition::RankingJobFactory)
      .to receive(:build)
      .with(
        ['--month', '2026-04', '--platform', 'github'],
        configuration: configuration,
        output: output,
        crawl_jobs: crawl_jobs
      ).and_return(monthly_command)

    described_class.build(configuration: configuration, output: output).call

    expect(output.string).to include('Resuming monthly_rankings --month 2026-04 --platform github')
    expect(monthly_command).to have_received(:call)
  end

  def stub_resume_environment
    configuration = instance_double(PolishOpenSourceRank::Configuration, database_path: 'db/test.sqlite3')
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    migration = instance_double(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration, bootstrap!: nil)
    crawl_jobs = instance_double(
      PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository,
      resumable: [{ command: 'monthly_rankings', arguments: ['--month', '2026-04', '--platform', 'github'] }]
    )

    allow(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
      .to receive(:open).with('db/test.sqlite3').and_return(database)
    allow(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration)
      .to receive(:new)
      .with(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      .and_return(migration)
    allow(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to receive(:new).with(database).and_return(crawl_jobs)

    [configuration, crawl_jobs]
  end
end

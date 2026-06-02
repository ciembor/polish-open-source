# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Interfaces::Composition::RankingJobFactory do
  it 'builds the command from configuration and infrastructure adapters' do
    configuration = command_configuration
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    source_request_log = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog
    )
    clients = stub_clients(source_request_log)
    stub_gateways(clients)
    stub_database(database)
    stub_ranking_adapters(database, source_request_log)
    allow(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot).to receive(:new).and_call_original

    command = described_class.build(['--month', '2026-04'], configuration: configuration, output: StringIO.new)

    expect(command).to be_a(PolishOpenSourceRank::Interfaces::CLI::MonthlyRankingsCommand)
    expect(PolishOpenSourceRank::Contexts::Ranking::Application::RunMonthlySnapshot).to have_received(:new).with(
      hash_including(
        source_runner: be_a(PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceSnapshotRunner),
        source_metric_backfill: be_a(
          PolishOpenSourceRank::Contexts::Ranking::Application::MonthlySourceMetricBackfill
        )
      )
    )
    expect(PolishOpenSourceRank::Infrastructure::GitHubGateway).to have_received(:new).with(clients.fetch(:github))
    expect(PolishOpenSourceRank::Infrastructure::GitLabGateway).to have_received(:new).with(clients.fetch(:gitlab))
    expect(PolishOpenSourceRank::Infrastructure::CodebergGateway).to have_received(:new).with(clients.fetch(:codeberg))
  end

  it 'builds a command for one selected platform' do
    configuration = command_configuration
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    source_request_log = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog
    )
    clients = stub_clients(source_request_log)
    stub_gateways(clients)
    stub_database(database)
    stub_ranking_adapters(database, source_request_log)

    command = described_class.build(
      ['--month', '2026-04', '--platform', 'gitlab'],
      configuration: configuration,
      output: StringIO.new
    )

    expect(command).to be_a(PolishOpenSourceRank::Interfaces::CLI::MonthlyRankingsCommand)
    expect(PolishOpenSourceRank::Infrastructure::GitHubGateway).not_to have_received(:new)
    expect(PolishOpenSourceRank::Infrastructure::GitLabGateway).to have_received(:new).with(clients.fetch(:gitlab))
    expect(PolishOpenSourceRank::Infrastructure::CodebergGateway).not_to have_received(:new)
  end

  it 'rejects unsupported selected platforms' do
    configuration = command_configuration
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    source_request_log = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog
    )
    clients = stub_clients(source_request_log)
    stub_gateways(clients)
    stub_database(database)
    stub_ranking_adapters(database, source_request_log)

    expect do
      described_class.build(['--platform', 'sourcehut'], configuration: configuration, output: StringIO.new)
    end.to raise_error(ArgumentError, 'Unsupported platform: sourcehut')
  end

  def command_configuration
    instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: 'db/test.sqlite3',
      github_token: 'token',
      github_base_url: 'https://api.github.test',
      gitlab_token: nil,
      gitlab_base_url: 'https://gitlab.test/api/v4',
      codeberg_token: nil,
      codeberg_base_url: 'https://codeberg.test/api/v1',
      requests_per_minute: 25,
      http_timeouts: { open_timeout: 5, read_timeout: 30, write_timeout: 30 }
    )
  end

  def stub_clients(source_request_log)
    clients = {
      github: instance_double(PolishOpenSourceRank::Infrastructure::GitHubClient),
      gitlab: instance_double(PolishOpenSourceRank::Infrastructure::GitLabClient),
      codeberg: instance_double(PolishOpenSourceRank::Infrastructure::CodebergClient)
    }
    allow(PolishOpenSourceRank::Infrastructure::GitHubClient).to receive(:new).and_return(clients.fetch(:github))
    allow(PolishOpenSourceRank::Infrastructure::GitLabClient).to receive(:new).and_return(clients.fetch(:gitlab))
    allow(PolishOpenSourceRank::Infrastructure::CodebergClient).to receive(:new).and_return(clients.fetch(:codeberg))
    stub_request_logs(clients, source_request_log)
    clients
  end

  def stub_request_logs(clients, source_request_log)
    clients.each_value { |client| allow(client).to receive(:request_log=).with(source_request_log) }
  end

  def stub_gateways(clients)
    allow(PolishOpenSourceRank::Infrastructure::GitHubGateway).to receive(:new).with(clients.fetch(:github))
    allow(PolishOpenSourceRank::Infrastructure::GitLabGateway).to receive(:new).with(clients.fetch(:gitlab))
    allow(PolishOpenSourceRank::Infrastructure::CodebergGateway).to receive(:new).with(clients.fetch(:codeberg))
  end

  def stub_database(database)
    migration = instance_double(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration, bootstrap!: nil)
    allow(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
      .to receive(:open).with('db/test.sqlite3').and_return(database)
    allow(PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration)
      .to receive(:new)
      .with(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      .and_return(migration)
  end

  def stub_ranking_adapters(database, source_request_log)
    snapshot_run_repository =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository)
    candidate_queue =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue)
    snapshot_repository =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository)
    ranking_retention =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention)
    monthly_snapshot_store =
      instance_double(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore)
    crawl_job_repository =
      instance_double(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)

    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository)
      .to receive(:new).with(database).and_return(snapshot_run_repository)
    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteCandidateQueue)
      .to receive(:new).with(database).and_return(candidate_queue)
    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository)
      .to receive(:new).with(database).and_return(snapshot_repository)
    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention)
      .to receive(:new).with(database).and_return(ranking_retention)
    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog)
      .to receive(:new).with(database).and_return(source_request_log)
    allow(PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::MonthlySnapshotStore)
      .to receive(:new)
      .with(
        run_repository: snapshot_run_repository,
        candidate_queue: candidate_queue,
        snapshot_repository: snapshot_repository,
        ranking_retention: ranking_retention
      )
      .and_return(monthly_snapshot_store)
    allow(PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository)
      .to receive(:new).with(database).and_return(crawl_job_repository)
  end
end

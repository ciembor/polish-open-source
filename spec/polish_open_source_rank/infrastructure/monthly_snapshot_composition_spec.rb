# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::MonthlySnapshotComposition do
  it 'builds the command from configuration and infrastructure adapters' do
    configuration = command_configuration
    clients = stub_clients
    stub_gateways(clients)

    command = described_class.build(['--month', '2026-04'], configuration: configuration, output: StringIO.new)

    expect(command).to be_a(PolishOpenSourceRank::Application::MonthlySnapshotCommand)
    expect(PolishOpenSourceRank::Infrastructure::GitHubGateway).to have_received(:new).with(clients.fetch(:github))
    expect(PolishOpenSourceRank::Infrastructure::GitLabGateway).to have_received(:new).with(clients.fetch(:gitlab))
    expect(PolishOpenSourceRank::Infrastructure::CodebergGateway).to have_received(:new).with(clients.fetch(:codeberg))
  end

  it 'builds a command for one selected platform' do
    configuration = command_configuration
    clients = stub_clients
    stub_gateways(clients)

    command = described_class.build(
      ['--month', '2026-04', '--platform', 'gitlab'],
      configuration: configuration,
      output: StringIO.new
    )

    expect(command).to be_a(PolishOpenSourceRank::Application::MonthlySnapshotCommand)
    expect(PolishOpenSourceRank::Infrastructure::GitHubGateway).not_to have_received(:new)
    expect(PolishOpenSourceRank::Infrastructure::GitLabGateway).to have_received(:new).with(clients.fetch(:gitlab))
    expect(PolishOpenSourceRank::Infrastructure::CodebergGateway).not_to have_received(:new)
  end

  it 'rejects unsupported selected platforms' do
    configuration = command_configuration
    clients = stub_clients
    stub_gateways(clients)

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
      requests_per_minute: 25
    )
  end

  def stub_clients
    store = instance_double(PolishOpenSourceRank::Infrastructure::SQLiteStore)
    clients = {
      github: instance_double(PolishOpenSourceRank::Infrastructure::GitHubClient),
      gitlab: instance_double(PolishOpenSourceRank::Infrastructure::GitLabClient),
      codeberg: instance_double(PolishOpenSourceRank::Infrastructure::CodebergClient)
    }
    allow(PolishOpenSourceRank::Infrastructure::SQLiteStore).to receive(:new).and_return(store)
    allow(store).to receive(:migrate!).and_return(store)
    allow(PolishOpenSourceRank::Infrastructure::GitHubClient).to receive(:new).and_return(clients.fetch(:github))
    allow(PolishOpenSourceRank::Infrastructure::GitLabClient).to receive(:new).and_return(clients.fetch(:gitlab))
    allow(PolishOpenSourceRank::Infrastructure::CodebergClient).to receive(:new).and_return(clients.fetch(:codeberg))
    clients
  end

  def stub_gateways(clients)
    allow(PolishOpenSourceRank::Infrastructure::GitHubGateway).to receive(:new).with(clients.fetch(:github))
    allow(PolishOpenSourceRank::Infrastructure::GitLabGateway).to receive(:new).with(clients.fetch(:gitlab))
    allow(PolishOpenSourceRank::Infrastructure::CodebergGateway).to receive(:new).with(clients.fetch(:codeberg))
  end
end

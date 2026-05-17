# frozen_string_literal: true

RSpec.describe PolishGithubRank::Infrastructure::MonthlySnapshotComposition do
  it 'builds the command from configuration and infrastructure adapters' do
    configuration = command_configuration
    clients = stub_clients
    stub_gateways(clients)

    command = described_class.build(['--month', '2026-04'], configuration: configuration, output: StringIO.new)

    expect(command).to be_a(PolishGithubRank::Application::MonthlySnapshotCommand)
    expect(PolishGithubRank::Infrastructure::GitHubGateway).to have_received(:new).with(clients.fetch(:github))
    expect(PolishGithubRank::Infrastructure::GitLabGateway).to have_received(:new).with(clients.fetch(:gitlab))
    expect(PolishGithubRank::Infrastructure::CodebergGateway).to have_received(:new).with(clients.fetch(:codeberg))
  end

  def command_configuration
    instance_double(
      PolishGithubRank::Configuration,
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
    store = instance_double(PolishGithubRank::Infrastructure::SQLiteStore)
    clients = {
      github: instance_double(PolishGithubRank::Infrastructure::GitHubClient),
      gitlab: instance_double(PolishGithubRank::Infrastructure::GitLabClient),
      codeberg: instance_double(PolishGithubRank::Infrastructure::CodebergClient)
    }
    allow(PolishGithubRank::Infrastructure::SQLiteStore).to receive(:new).and_return(store)
    allow(store).to receive(:migrate!).and_return(store)
    allow(PolishGithubRank::Infrastructure::GitHubClient).to receive(:new).and_return(clients.fetch(:github))
    allow(PolishGithubRank::Infrastructure::GitLabClient).to receive(:new).and_return(clients.fetch(:gitlab))
    allow(PolishGithubRank::Infrastructure::CodebergClient).to receive(:new).and_return(clients.fetch(:codeberg))
    clients
  end

  def stub_gateways(clients)
    allow(PolishGithubRank::Infrastructure::GitHubGateway).to receive(:new).with(clients.fetch(:github))
    allow(PolishGithubRank::Infrastructure::GitLabGateway).to receive(:new).with(clients.fetch(:gitlab))
    allow(PolishGithubRank::Infrastructure::CodebergGateway).to receive(:new).with(clients.fetch(:codeberg))
  end
end

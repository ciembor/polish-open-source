# frozen_string_literal: true

RSpec.describe PolishGithubRank::Application::MonthlySnapshotCommand do
  it 'wires configuration, persistence, GitHub adapter, and monthly job' do
    store = instance_double(PolishGithubRank::Infrastructure::SQLiteStore, migrate!: nil)
    client = instance_double(PolishGithubRank::Infrastructure::GitHubClient)
    github = instance_double(PolishGithubRank::Infrastructure::GitHubGateway)
    job = instance_double(PolishGithubRank::Application::MonthlySnapshotJob)
    configuration = instance_double(
      PolishGithubRank::Configuration,
      database_path: 'db/test.sqlite3',
      github_token: 'token',
      github_base_url: 'https://api.github.test',
      requests_per_minute: 25
    )

    allow(PolishGithubRank::Configuration).to receive(:load).and_return(configuration)
    allow(PolishGithubRank::Infrastructure::SQLiteStore).to receive(:new).and_return(store)
    allow(store).to receive(:migrate!).and_return(store)
    allow(PolishGithubRank::Infrastructure::GitHubClient).to receive(:new).and_return(client)
    allow(PolishGithubRank::Infrastructure::GitHubGateway).to receive(:new).and_return(github)
    allow(PolishGithubRank::Application::MonthlySnapshotJob).to receive(:new).and_return(job)
    allow(job).to receive(:call)

    expect do
      described_class.call(['--month', '2026-04'])
    end.to output(/Finished monthly ranking run for 2026-04/).to_stdout
    expect(job).to have_received(:call).with(have_attributes(key: '2026-04'))
  end
end

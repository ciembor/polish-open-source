# frozen_string_literal: true

class FakeGitHubClient
  attr_reader :params, :paths

  def initialize
    @responses = []
    @paths = []
    @params = []
  end

  def queue(body:, link: nil)
    @responses << PolishGithubRank::Infrastructure::GitHubClient::Response.new(
      status: 200,
      headers: { 'link' => link },
      body: body
    )
  end

  def get(path, params: {}, accept: PolishGithubRank::Infrastructure::GitHubClient::DEFAULT_ACCEPT)
    @paths << path
    @params << params
    @accept = accept
    @responses.shift
  end
end

RSpec.describe PolishGithubRank::Infrastructure::GitHubGateway do
  let(:client) { FakeGitHubClient.new }
  let(:gateway) { described_class.new(client) }
  let(:period) { PolishGithubRank::Application::MonthPeriod.parse('2026-04') }

  it 'discovers users from paginated location search with the GitHub search cap' do
    10.times do |index|
      client.queue(body: { 'items' => [{ 'id' => index, 'login' => "user#{index}" }] }, link: '<x?page=11>; rel="next"')
    end

    users = gateway.search_users_by_location('Poland')

    expect(users.map { |user| user.fetch('login') }).to eq((0..9).map { |index| "user#{index}" })
    expect(client.paths).to all(eq('/search/users'))
  end

  it 'loads repositories across pages' do
    client.queue(body: [{ 'full_name' => 'alice/one' }], link: '<x?page=2>; rel="next"')
    client.queue(body: [{ 'full_name' => 'alice/two' }])

    expect(gateway.repositories_for('alice').map { |repo| repo.fetch('full_name') }).to eq(%w[alice/one alice/two])
  end

  it 'loads a single user profile' do
    client.queue(body: { 'login' => 'alice' })

    expect(gateway.user('alice')).to eq('login' => 'alice')
  end

  it 'counts monthly repository stars from a single stargazer page' do
    client.queue(
      body: [
        { 'starred_at' => '2026-04-10T10:00:00Z' },
        { 'starred_at' => '2026-05-01T00:00:00Z' }
      ]
    )

    expect(gateway.repository_stars_delta('alice/app', period)).to eq(1)
  end

  it 'walks stargazer pages backwards and stops after older pages' do
    client.queue(body: [], link: '<x?page=3>; rel="last"')
    client.queue(body: [{ 'starred_at' => '2026-04-20T10:00:00Z' }])
    client.queue(body: [{ 'starred_at' => '2026-03-20T10:00:00Z' }])

    expect(gateway.repository_stars_delta('alice/app', period)).to eq(1)
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 3, 2])
  end

  it 'counts public activity in the month across public events' do
    client.queue(
      body: [
        { 'created_at' => '2026-05-02T10:00:00Z' },
        { 'created_at' => '2026-04-02T10:00:00Z' }
      ],
      link: '<x?page=2>; rel="next"'
    )
    client.queue(body: [{ 'created_at' => '2026-03-02T10:00:00Z' }], link: '<x?page=3>; rel="next"')

    expect(gateway.public_activity_count('alice', period)).to eq(1)
  end
end

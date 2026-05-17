# frozen_string_literal: true

class FakeGitHubClient
  attr_reader :accepts, :params, :paths

  def initialize
    @responses = []
    @accepts = []
    @paths = []
    @params = []
  end

  def queue(body:, link: nil)
    @responses << PolishOpenSourceRank::Infrastructure::GitHubClient::Response.new(
      status: 200,
      headers: { 'link' => link },
      body: body
    )
  end

  def queue_without_link(body:)
    @responses << PolishOpenSourceRank::Infrastructure::GitHubClient::Response.new(
      status: 200,
      headers: {},
      body: body
    )
  end

  def queue_error(error)
    @responses << error
  end

  def get(path, params: {}, accept: PolishOpenSourceRank::Infrastructure::GitHubClient::DEFAULT_ACCEPT)
    @paths << path
    @params << params
    @accepts << accept
    response = @responses.shift
    raise response if response.is_a?(StandardError)

    response
  end
end

RSpec.describe PolishOpenSourceRank::Infrastructure::GitHubGateway do
  let(:client) { FakeGitHubClient.new }
  let(:gateway) { described_class.new(client) }
  let(:period) { PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04') }

  it 'identifies its platform' do
    expect(gateway.platform).to eq('github')
  end

  it 'discovers users from paginated location search with the GitHub search cap' do
    10.times do |index|
      client.queue(body: { 'items' => [{ 'id' => index, 'login' => "user#{index}" }] }, link: '<x?page=11>; rel="next"')
    end

    users = gateway.search_users_by_location('Poland')

    expect(users).to eq((0..9).map { |index| { source_id: index, login: "user#{index}" } })
    expect(client.paths).to all(eq('/search/users'))
    expect(client.params.first).to eq(q: 'type:user location:"Poland"', per_page: 100, page: 1)
    expect(client.params.last).to eq(q: 'type:user location:"Poland"', per_page: 100, page: 10)
  end

  it 'treats missing search items as an empty result' do
    client.queue(body: {})

    expect(gateway.search_users_by_location('Poland')).to eq([])
  end

  it 'loads repositories across pages' do
    client.queue(body: [repository(1, 'alice/one')], link: '<x?page=2>; rel="next"')
    client.queue(body: [repository(2, 'alice/two')])

    expect(gateway.repositories_for(login: 'alice')).to eq(
      [
        expected_repository(1, 'alice/one'),
        expected_repository(2, 'alice/two')
      ]
    )
    expect(client.paths).to eq(['/users/alice/repos', '/users/alice/repos'])
    expect(client.params).to eq(
      [
        { type: 'owner', sort: 'full_name', direction: 'asc', per_page: 100, page: 1 },
        { type: 'owner', sort: 'full_name', direction: 'asc', per_page: 100, page: 2 }
      ]
    )
  end

  it 'does not continue pagination for non-next links' do
    client.queue(body: [repository(1, 'alice/one')], link: '<x?page=2>; rel="last"')

    expect(gateway.repositories_for(login: 'alice')).to eq([expected_repository(1, 'alice/one')])
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1])
  end

  it 'does not require a link header for unpaginated responses' do
    client.queue_without_link(body: [repository(1, 'alice/one')])

    expect(gateway.repositories_for(login: 'alice')).to eq([expected_repository(1, 'alice/one')])
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1])
  end

  it 'continues pagination when an internal page block returns a non-stop truthy value' do
    client.queue(body: [], link: '<x?page=2>; rel="next"')
    client.queue(body: [])

    gateway.send(:each_page, '/custom', {}) { true }

    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 2])
  end

  it 'keeps missing optional repository fields as nil' do
    client.queue(body: [repository(1, 'alice/minimal').except('description', 'homepage', 'language')])

    expect(gateway.repositories_for(login: 'alice')).to eq(
      [
        expected_repository(1, 'alice/minimal').merge(description: nil, homepage: nil, language: nil)
      ]
    )
  end

  it 'normalizes repository stars to an integer' do
    client.queue(body: [repository(1, 'alice/one').merge('stargazers_count' => '42')])

    expect(gateway.repositories_for(login: 'alice').first.fetch(:stars)).to eq(42)
  end

  it 'rejects malformed repository star counts' do
    client.queue(body: [repository(1, 'alice/one').merge('stargazers_count' => '42 stars')])

    expect { gateway.repositories_for(login: 'alice') }.to raise_error(ArgumentError)
  end

  it 'loads a single user profile' do
    client.queue(body: profile(1, 'alice'))

    expect(gateway.user('alice')).to eq(
      source_id: 1,
      login: 'alice',
      name: 'Alice',
      location: 'Poland',
      email: 'alice@example.com',
      homepage: 'https://alice.example',
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example/alice.png'
    )
    expect(client.paths).to eq(['/users/alice'])
  end

  it 'keeps missing optional profile fields as nil' do
    client.queue(body: profile(1, 'alice').except('name', 'location', 'email', 'blog', 'avatar_url'))

    expect(gateway.user('alice')).to eq(
      source_id: 1,
      login: 'alice',
      name: nil,
      location: nil,
      email: nil,
      homepage: nil,
      html_url: 'https://github.com/alice',
      avatar_url: nil
    )
  end

  it 'translates missing users to the source contract error' do
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::GitHubClient::NotFound.new('missing', status: 404, body: '{}')
    )

    expect { gateway.user('missing') }.to raise_error(PolishOpenSourceRank::Application::SourceNotFound)
  end

  it 'counts monthly repository stars from a single stargazer page' do
    client.queue(
      body: [
        { 'starred_at' => '2026-04-10T10:00:00Z' },
        { 'starred_at' => '2026-05-01T00:00:00Z' }
      ]
    )

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(1)
    expect(client.paths).to eq(['/repos/alice/app/stargazers'])
    expect(client.params).to eq([{ per_page: 100, page: 1 }])
    expect(client.accepts).to eq([described_class::STAR_ACCEPT])
  end

  it 'does not require pagination headers for single-page stargazers' do
    client.queue_without_link(body: [{ 'starred_at' => '2026-04-10T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(1)
  end

  it 'rejects repository full names outside the GitHub owner/repo shape' do
    expect { gateway.repository_stars_delta({ full_name: 'alice/team/app' }, period) }
      .to raise_error(ArgumentError, 'Invalid GitHub repository full_name: "alice/team/app"')
  end

  it 'walks stargazer pages backwards and stops after older pages' do
    client.queue(body: [], link: '<x?page=3>; rel="last"')
    client.queue(body: [{ 'starred_at' => '2026-04-20T10:00:00Z' }])
    client.queue(body: [{ 'starred_at' => '2026-03-20T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(1)
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 3, 2])
  end

  it 'walks stargazer pages backwards through page one' do
    client.queue(body: [], link: '<x?page=2>; rel="last"')
    client.queue(body: [{ 'starred_at' => '2026-04-20T10:00:00Z' }])
    client.queue(body: [{ 'starred_at' => '2026-04-01T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(2)
    expect(client.paths).to eq(['/repos/alice/app/stargazers', '/repos/alice/app/stargazers',
                                '/repos/alice/app/stargazers'])
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 2, 1])
  end

  it 'parses multi-digit last stargazer page numbers' do
    client.queue(body: [], link: '<x?page=12>; rel="last"')
    client.queue(body: [{ 'starred_at' => '2026-03-20T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(0)
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 12])
  end

  it 'continues past empty stargazer pages while walking backwards' do
    client.queue(body: [], link: '<x?page=3>; rel="last"')
    client.queue(body: [])
    client.queue(body: [{ 'starred_at' => '2026-04-20T10:00:00Z' }])
    client.queue(body: [{ 'starred_at' => '2026-03-20T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(1)
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 3, 2, 1])
  end

  it 'continues past mixed old and current stargazer pages while walking backwards' do
    client.queue(body: [], link: '<x?page=3>; rel="last"')
    client.queue(
      body: [
        { 'starred_at' => '2026-04-20T10:00:00Z' },
        { 'starred_at' => '2026-03-20T10:00:00Z' }
      ]
    )
    client.queue(body: [{ 'starred_at' => '2026-04-10T10:00:00Z' }])
    client.queue(body: [{ 'starred_at' => '2026-03-10T10:00:00Z' }])

    expect(gateway.repository_stars_delta({ full_name: 'alice/app' }, period)).to eq(2)
    expect(client.params.map { |params| params.fetch(:page) }).to eq([1, 3, 2, 1])
  end

  it 'treats unavailable stargazer history as zero monthly delta' do
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new(
        'blocked',
        status: 451,
        body: '{"message":"Repository access blocked"}'
      )
    )

    expect(gateway.repository_stars_delta({ full_name: 'alice/blocked' }, period)).to eq(0)
  end

  it 'treats forbidden stargazer history as zero monthly delta' do
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new(
        'forbidden',
        status: 403,
        body: '{"message":"Resource not accessible"}'
      )
    )

    expect(gateway.repository_stars_delta({ full_name: 'alice/forbidden' }, period)).to eq(0)
  end

  it 'reraises unexpected stargazer history errors' do
    error = PolishOpenSourceRank::Infrastructure::GitHubClient::Error.new(
      'server error',
      status: 500,
      body: '{"message":"Server Error"}'
    )
    client.queue_error(error)

    expect { gateway.repository_stars_delta({ full_name: 'alice/app' }, period) }.to raise_error(error)
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

    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(1)
    expect(client.paths).to eq(['/users/alice/events/public', '/users/alice/events/public'])
    expect(client.params).to eq([{ per_page: 100, page: 1 }, { per_page: 100, page: 2 }])
  end

  it 'stops public activity pagination once a page is entirely older than the period' do
    client.queue(body: [{ 'created_at' => '2026-03-02T10:00:00Z' }], link: '<x?page=2>; rel="next"')

    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(0)
    expect(client.paths).to eq(['/users/alice/events/public'])
  end

  it 'continues public activity pagination after empty pages' do
    client.queue(body: [], link: '<x?page=2>; rel="next"')
    client.queue(body: [{ 'created_at' => '2026-04-02T10:00:00Z' }])

    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(1)
    expect(client.params).to eq([{ per_page: 100, page: 1 }, { per_page: 100, page: 2 }])
  end

  it 'continues public activity pagination after mixed old and current pages' do
    client.queue(
      body: [
        { 'created_at' => '2026-04-02T10:00:00Z' },
        { 'created_at' => '2026-03-02T10:00:00Z' }
      ],
      link: '<x?page=2>; rel="next"'
    )
    client.queue(body: [{ 'created_at' => '2026-04-03T10:00:00Z' }])

    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(2)
    expect(client.params).to eq([{ per_page: 100, page: 1 }, { per_page: 100, page: 2 }])
  end

  def expected_repository(id, full_name)
    {
      source_id: id,
      name: full_name.split('/').last,
      full_name: full_name,
      description: "#{full_name} description",
      html_url: "https://github.com/#{full_name}",
      homepage: "https://#{full_name.tr('/', '-')}.example",
      language: 'Ruby',
      fork: false,
      archived: false,
      stars: 1
    }
  end

  def profile(id, login)
    {
      'id' => id,
      'login' => login,
      'name' => login.capitalize,
      'location' => 'Poland',
      'email' => "#{login}@example.com",
      'blog' => "https://#{login}.example",
      'html_url' => "https://github.com/#{login}",
      'avatar_url' => "https://avatars.example/#{login}.png"
    }
  end

  def repository(id, full_name)
    {
      'id' => id,
      'name' => full_name.split('/').last,
      'full_name' => full_name,
      'description' => "#{full_name} description",
      'html_url' => "https://github.com/#{full_name}",
      'homepage' => "https://#{full_name.tr('/', '-')}.example",
      'language' => 'Ruby',
      'fork' => false,
      'archived' => false,
      'stargazers_count' => 1
    }
  end
end

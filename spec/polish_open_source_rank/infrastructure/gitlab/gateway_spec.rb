# frozen_string_literal: true

class FakeGitLabClient
  attr_reader :params, :paths

  def initialize
    @responses = []
    @paths = []
    @params = []
  end

  def queue(body:, next_page: nil)
    @responses << PolishOpenSourceRank::Infrastructure::GitLabClient::Response.new(
      status: 200,
      headers: { 'x-next-page' => next_page.to_s },
      body: body
    )
  end

  def queue_error(error)
    @responses << error
  end

  def get(path, params: {})
    @paths << path
    @params << params
    response = @responses.shift
    raise response if response.is_a?(StandardError)

    response
  end
end

RSpec.describe PolishOpenSourceRank::Infrastructure::GitLabGateway do
  let(:client) { FakeGitLabClient.new }
  let(:gateway) { described_class.new(client) }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'identifies its platform' do
    expect(gateway.platform).to eq('gitlab')
  end

  it 'discovers GitLab users through paginated search' do
    client.queue(body: [{ 'id' => 1, 'username' => 'alice' }], next_page: '2')
    client.queue(body: [{ 'id' => 2, 'username' => 'bob' }])

    expect(gateway.search_users_by_location('Poland').map { |user| user.fetch(:login) }).to eq(%w[alice bob])
    expect(client.paths).to all(eq('/users'))
  end

  it 'loads users, repositories, and public activity' do
    client.queue(body: profile(1, 'alice'))
    expect(gateway.user('alice', 1)).to include(source_id: 1, login: 'alice')

    client.queue(body: [repository(10, 'alice/app')])
    expect(gateway.repositories_for(source_id: 1).first).to include(full_name: 'alice/app')

    client.queue(body: [{ 'created_at' => '2026-04-10T10:00:00Z' }], next_page: '2')
    client.queue(body: [{ 'created_at' => '2026-03-10T10:00:00Z' }])
    expect(gateway.public_activity_count({ source_id: 1 }, period)).to eq(1)
  end

  it 'translates missing users to the source contract error' do
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::GitLabClient::NotFound.new('missing', status: 404, body: '{}')
    )

    expect { gateway.user('missing', 404) }.to raise_error(PolishOpenSourceRank::Contexts::Ranking::Application::SourceNotFound)
  end

  it 'uses zero for unsupported GitLab monthly star deltas and missing activity' do
    expect(gateway.repository_stars_delta({}, period)).to eq(0)
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::GitLabClient::NotFound.new('missing', status: 404, body: '{}')
    )

    expect(gateway.public_activity_count({ source_id: 404 }, period)).to eq(0)
  end

  def profile(id, login)
    {
      'id' => id,
      'username' => login,
      'name' => login.capitalize,
      'location' => 'Poland',
      'public_email' => nil,
      'website_url' => nil,
      'web_url' => "https://gitlab.com/#{login}",
      'avatar_url' => nil
    }
  end

  def repository(id, full_name)
    {
      'id' => id,
      'name' => full_name.split('/').last,
      'path_with_namespace' => full_name,
      'description' => nil,
      'web_url' => "https://gitlab.com/#{full_name}",
      'language' => 'Ruby',
      'forked_from_project' => nil,
      'archived' => false,
      'star_count' => 1
    }
  end
end

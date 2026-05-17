# frozen_string_literal: true

class FakeCodebergClient
  attr_reader :params, :paths

  def initialize
    @responses = []
    @paths = []
    @params = []
  end

  def queue(body:)
    @responses << PolishOpenSourceRank::Infrastructure::CodebergClient::Response.new(
      status: 200,
      headers: {},
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

RSpec.describe PolishOpenSourceRank::Infrastructure::CodebergGateway do
  let(:client) { FakeCodebergClient.new }
  let(:gateway) { described_class.new(client) }
  let(:period) { PolishOpenSourceRank::Application::MonthPeriod.parse('2026-04') }

  it 'identifies its platform' do
    expect(gateway.platform).to eq('codeberg')
  end

  it 'discovers Codeberg users through search result pages' do
    client.queue(body: { 'ok' => true, 'data' => [{ 'id' => 1, 'login' => 'alice' }] })

    expect(gateway.search_users_by_location('Poland').map { |user| user.fetch(:login) }).to eq(%w[alice])
    expect(client.paths).to eq(['/users/search'])
    expect(client.params.first).to include(q: 'Poland', limit: 50, page: 1)
  end

  it 'caps user discovery when Codeberg keeps returning full pages' do
    10.times do |page|
      users = Array.new(50) { |index| { 'id' => (page * 50) + index, 'login' => "user-#{page}-#{index}" } }
      client.queue(body: { 'ok' => true, 'data' => users })
    end

    expect(gateway.search_users_by_location('Poland').length).to eq(500)
    expect(client.params.last).to include(page: 10)
  end

  it 'loads users, repositories, and public activity' do
    client.queue(body: profile(1, 'alice'))
    expect(gateway.user('alice', 1)).to include(source_id: 1, login: 'alice')

    client.queue(body: { 'ok' => true, 'data' => [repository(10, 'alice/app')] })
    expect(gateway.repositories_for(source_id: 1).first).to include(full_name: 'alice/app')

    client.queue(body: [{ 'created' => '2026-04-10T10:00:00Z' }])
    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(1)
  end

  it 'translates missing users to the source contract error' do
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::CodebergClient::NotFound.new('missing', status: 404, body: '{}')
    )

    expect { gateway.user('missing', 404) }.to raise_error(PolishOpenSourceRank::Application::SourceNotFound)
  end

  it 'stops activity pagination after a full page older than the ranking period' do
    old_events = Array.new(50) { { 'created' => '2026-03-10T10:00:00Z' } }
    client.queue(body: old_events)

    expect(gateway.public_activity_count({ login: 'alice' }, period)).to eq(0)
    expect(client.params.last).to include(page: 1)
  end

  it 'uses zero for unsupported Codeberg monthly star deltas and missing activity' do
    expect(gateway.repository_stars_delta({}, period)).to eq(0)
    client.queue_error(
      PolishOpenSourceRank::Infrastructure::CodebergClient::NotFound.new('missing', status: 404, body: '{}')
    )

    expect(gateway.public_activity_count({ login: 'missing' }, period)).to eq(0)
  end

  def profile(id, login)
    {
      'id' => id,
      'login' => login,
      'full_name' => login.capitalize,
      'location' => 'Poland',
      'email' => nil,
      'website' => nil,
      'html_url' => "https://codeberg.org/#{login}",
      'avatar_url' => nil
    }
  end

  def repository(id, full_name)
    {
      'id' => id,
      'name' => full_name.split('/').last,
      'full_name' => full_name,
      'description' => nil,
      'html_url' => "https://codeberg.org/#{full_name}",
      'website' => nil,
      'language' => 'Ruby',
      'fork' => false,
      'archived' => false,
      'stars_count' => 1
    }
  end
end

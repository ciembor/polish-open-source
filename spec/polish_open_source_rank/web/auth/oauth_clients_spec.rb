# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Auth::GitHubOAuthClient do
  around do |example|
    old_env = ENV.to_h
    ENV['GITHUB_OAUTH_CLIENT_ID'] = 'github-client'
    ENV['GITHUB_OAUTH_CLIENT_SECRET'] = 'github-secret'
    ENV['DISCORD_OAUTH_CLIENT_ID'] = 'discord-client'
    ENV['DISCORD_OAUTH_CLIENT_SECRET'] = 'discord-secret'
    ENV['DISCORD_BOT_TOKEN'] = 'bot-token'
    ENV['DISCORD_GUILD_ID'] = 'guild-1'
    example.run
  ensure
    ENV.replace(old_env)
  end

  it 'builds GitHub authorization URLs and loads the authenticated user' do
    configuration = PolishOpenSourceRank::Configuration.load
    client = described_class.new(configuration)
    responses = [
      json_response('{"access_token":"github-token"}'),
      json_response('{"id":1,"login":"alice","ignored":true}')
    ]
    requests = capture_http_requests(responses)

    url = client.authorize_url(state: 'state-1', redirect_uri: 'https://rank/auth/github/callback')

    expect(url).to include('client_id=github-client')
    expect(url).to include('scope=read%3Auser')
    token = client.exchange_code(code: 'code-1', redirect_uri: 'https://rank/auth/github/callback')
    expect(token).to eq('github-token')
    expect(client.user('github-token')).to eq('id' => 1, 'login' => 'alice')
    expect(requests.map(&:method)).to eq(%w[POST GET])
  end

  it 'builds Discord authorization URLs and loads the authenticated user' do
    configuration = PolishOpenSourceRank::Configuration.load
    client = PolishOpenSourceRank::Web::Auth::DiscordOAuthClient.new(configuration)
    responses = [
      json_response('{"access_token":"discord-token"}'),
      json_response('{"id":"u1","username":"alice","global_name":"Alice","ignored":true}')
    ]
    requests = capture_http_requests(responses)

    url = client.authorize_url(state: 'state-2', redirect_uri: 'https://rank/auth/discord/callback')

    expect(url).to include('client_id=discord-client')
    expect(url).to include('scope=identify+guilds.join')
    expect(client.exchange_code(code: 'code-2', redirect_uri: 'https://rank/auth/discord/callback')).to include(
      'access_token' => 'discord-token'
    )
    expect(client.user('discord-token')).to eq('id' => 'u1', 'username' => 'alice', 'global_name' => 'Alice')
    expect(requests.map(&:method)).to eq(%w[POST GET])
  end

  it 'creates one-use invites and syncs Discord guild members' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Web::Auth::DiscordGateway.new(configuration)
    responses = [
      json_response('{"code":"abc","url":"https://discord.gg/abc"}'),
      json_response('{}'),
      empty_response,
      empty_response,
      empty_response,
      empty_response,
      empty_response
    ]
    requests = capture_http_requests(responses)

    expect(gateway.create_invite(channel_id: 'channel-1')).to eq(code: 'abc', url: 'https://discord.gg/abc')
    expect(gateway.invite_available?('abc')).to be(true)
    gateway.sync_member(
      discord_user_id: 'discord-1',
      access_token: 'user-token',
      github_login: 'alice',
      desired_role_ids: %w[role-1 role-2],
      managed_role_ids: %w[role-1 role-2 role-3]
    )

    expect(requests.map(&:method)).to eq(%w[POST GET PUT PATCH DELETE PUT PUT])
    expect(requests.fetch(0).body).to include('"max_uses":1')
    expect(requests.fetch(2).body).to include('user-token')
    expect(requests.fetch(3).body).to include('alice')
  end

  it 'builds an invite URL when Discord only returns the invite code' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Web::Auth::DiscordGateway.new(configuration)
    capture_http_requests([json_response('{"code":"abc"}')])

    expect(gateway.create_invite(channel_id: 'channel-1')).to eq(code: 'abc', url: 'https://discord.gg/abc')
  end

  it 'treats missing Discord invites as unavailable and raises typed errors' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Web::Auth::DiscordGateway.new(configuration)
    capture_http_requests([response('404', 'Not Found', '{}')])

    expect(gateway.invite_available?('used')).to be(false)

    capture_http_requests([response('500', 'Server Error', 'nope')])
    expect { gateway.invite_available?('broken') }.to raise_error(PolishOpenSourceRank::Web::Auth::DiscordGateway::Error)

    capture_http_requests([response('500', 'Server Error', 'nope')])
    expect do
      gateway.sync_member(
        discord_user_id: 'discord-1',
        access_token: 'user-token',
        github_login: 'alice',
        desired_role_ids: [],
        managed_role_ids: []
      )
    end.to raise_error(PolishOpenSourceRank::Web::Auth::DiscordGateway::Error)
  end

  it 'maps configured Discord role keys to role IDs' do
    ENV['DISCORD_ROLE_TOP_10_PL'] = 'top-10-role'
    ENV['DISCORD_ROLE_TOP_100_CITY_KRAKOW'] = 'krakow-role'
    map = PolishOpenSourceRank::Web::Auth::DiscordRoleMap.new

    expect(map.role_ids(%w[DISCORD_ROLE_TOP_10_PL MISSING])).to eq(['top-10-role'])
    expect(map.managed_role_ids).to include('top-10-role', 'krakow-role')
  end

  def capture_http_requests(responses)
    requests = []
    allow(Net::HTTP).to receive(:start) do |_host, _port, _options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        responses.shift
      end
      block.call(http)
    end
    requests
  end

  def json_response(body)
    response('200', 'OK', body)
  end

  def empty_response
    response('204', 'No Content', '')
  end

  def response(code, message, body)
    klass = code.start_with?('2') ? Net::HTTPOK : Net::HTTPInternalServerError
    klass = Net::HTTPNotFound if code == '404'
    klass.new('1.1', code, message).tap do |response|
      response.body = body
      response.instance_variable_set(:@read, true)
    end
  end
end

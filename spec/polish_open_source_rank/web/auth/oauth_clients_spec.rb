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
    requests, = capture_http_requests(responses)

    url = client.authorize_url(state: 'state-1', redirect_uri: 'https://rank/auth/github/callback')

    expect(url).to include('client_id=github-client')
    expect(url).to include('scope=read%3Auser')
    token = client.exchange_code(code: 'code-1', redirect_uri: 'https://rank/auth/github/callback')
    expect(token).to eq('github-token')
    expect(client.user('github-token')).to include(
      'id' => 1,
      'login' => 'alice',
      'html_url' => 'https://github.com/alice'
    )
    expect(requests.map(&:method)).to eq(%w[POST GET])
  end

  it 'builds Discord authorization URLs and loads the authenticated user' do
    configuration = PolishOpenSourceRank::Configuration.load
    client = PolishOpenSourceRank::Web::Auth::DiscordOAuthClient.new(configuration)
    responses = [
      json_response('{"access_token":"discord-token"}'),
      json_response('{"id":"u1","username":"alice","global_name":"Alice","ignored":true}')
    ]
    requests, = capture_http_requests(responses)

    url = client.authorize_url(state: 'state-2', redirect_uri: 'https://rank/auth/discord/callback')

    expect(url).to include('client_id=discord-client')
    expect(url).to include('scope=identify+guilds.join')
    expect(client.exchange_code(code: 'code-2', redirect_uri: 'https://rank/auth/discord/callback')).to include(
      'access_token' => 'discord-token'
    )
    expect(client.user('discord-token')).to eq('id' => 'u1', 'username' => 'alice', 'global_name' => 'Alice')
    expect(requests.map(&:method)).to eq(%w[POST GET])
  end

  it 'maps fixture Discord OAuth and member payloads through public adapters' do
    configuration = PolishOpenSourceRank::Configuration.load
    oauth_client = PolishOpenSourceRank::Web::Auth::DiscordOAuthClient.new(configuration)
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    responses = [
      json_response(JSON.generate(fixture_json('external_payloads/discord_oauth_user.json'))),
      json_response(JSON.generate(fixture_json('external_payloads/discord_member.json'))),
      empty_response
    ]
    requests, = capture_http_requests(responses)

    expect(oauth_client.user('discord-token')).to eq(
      'id' => 'discord-1',
      'username' => 'alice',
      'global_name' => 'Alice Example'
    )
    gateway.sync_joined_member(
      discord_user_id: 'discord-1',
      github_login: 'alice',
      desired_role_ids: ['role-1'],
      managed_role_ids: %w[role-1 role-3]
    )

    expect(requests.map(&:method)).to eq(%w[GET GET PATCH])
    expect(JSON.parse(requests.fetch(2).body)).to eq(
      'nick' => 'alice',
      'roles' => %w[unmanaged-role role-1]
    )
  end

  it 'uses configured HTTP timeouts for OAuth and Discord API requests' do
    ENV['HTTP_OPEN_TIMEOUT'] = '7'
    ENV['HTTP_READ_TIMEOUT'] = '31'
    ENV['HTTP_WRITE_TIMEOUT'] = '29'
    ENV['USER_ACTION_HTTP_OPEN_TIMEOUT'] = '2'
    ENV['USER_ACTION_HTTP_READ_TIMEOUT'] = '8'
    ENV['USER_ACTION_HTTP_WRITE_TIMEOUT'] = '6'
    configuration = PolishOpenSourceRank::Configuration.load
    github_client = described_class.new(configuration)
    discord_client = PolishOpenSourceRank::Web::Auth::DiscordOAuthClient.new(configuration)
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    responses = [
      json_response('{"access_token":"github-token"}'),
      json_response('{"access_token":"discord-token"}'),
      response('404', 'Not Found', '{}')
    ]
    requests, options = capture_http_requests(responses)

    github_client.exchange_code(code: 'code-1', redirect_uri: 'https://rank/auth/github/callback')
    discord_client.exchange_code(code: 'code-2', redirect_uri: 'https://rank/auth/discord/callback')
    expect(gateway.invite_available?('used')).to be(false)

    expect(requests.map(&:method)).to eq(%w[POST POST GET])
    expect(options.first(2)).to all(include(use_ssl: true, open_timeout: 2, read_timeout: 8, write_timeout: 6))
    expect(options.fetch(2)).to include(use_ssl: true, open_timeout: 7, read_timeout: 31, write_timeout: 29)
  end

  it 'creates one-use invites and syncs Discord guild members' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    responses = [
      json_response('{"code":"abc","url":"https://discord.gg/abc"}'),
      json_response('{}'),
      empty_response,
      json_response('{"roles":["role-3","unmanaged-role"]}'),
      empty_response
    ]
    requests, = capture_http_requests(responses)

    expect(gateway.create_invite(channel_id: 'channel-1')).to eq(code: 'abc', url: 'https://discord.gg/abc')
    expect(gateway.invite_available?('abc')).to be(true)
    gateway.sync_member(
      discord_user_id: 'discord-1',
      access_token: 'user-token',
      github_login: 'alice',
      desired_role_ids: %w[role-1 role-2],
      managed_role_ids: %w[role-1 role-2 role-3]
    )

    expect(requests.map(&:method)).to eq(%w[POST GET PUT GET PATCH])
    expect(requests.fetch(0).body).to include('"max_uses":1')
    expect(requests.fetch(2).body).to include('user-token')
    expect(requests.fetch(4).body).to include('alice', 'role-1', 'role-2', 'unmanaged-role')
    expect(requests.fetch(4).body).not_to include('role-3')
  end

  it 'builds an invite URL when Discord only returns the invite code' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    capture_http_requests([json_response('{"code":"abc"}')])

    expect(gateway.create_invite(channel_id: 'channel-1')).to eq(code: 'abc', url: 'https://discord.gg/abc')
  end

  it 'posts a GitHub-rich welcome message with role-enabled channels' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    requests, = capture_http_requests(welcome_responses)

    gateway.post_welcome_message(
      channel_id: 'welcome-channel',
      discord_user_id: 'discord-1',
      profile: welcome_profile,
      access: { country_rank: 73, city: 'Krakow', city_rank: 11 },
      role_ids: ['role-1']
    )

    body = JSON.parse(requests.fetch(2).body)
    embed = body.fetch('embeds').first
    expect(requests.map(&:method)).to eq(%w[GET GET POST])
    expect(body.fetch('content')).to include('<@discord-1>', 'https://github.com/alice')
    expect(embed.fetch('thumbnail')).to eq('url' => 'https://avatars.example/alice.png')
    expect(embed.fetch('fields')).to include(
      hash_including('name' => 'Role', 'value' => include('Top 100 PL')),
      hash_including('name' => 'Kanaly do pisania', 'value' => include('<#channel-1>')),
      hash_including('name' => 'Najlepsze projekty', 'value' => include('alice/app', '12 345 stars'))
    )
  end

  it 'builds a neutral welcome message for users without ranking roles' do
    message = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordWelcomeMessage.new(
      discord_user_id: 'discord-1',
      profile: welcome_profile.merge(repositories: []),
      access: {},
      role_names: [],
      writable_channels: []
    ).payload

    embed = message.fetch(:embeds).first
    expect(embed.fetch(:color)).to eq(0)
    expect(embed.fetch(:fields)).to include(
      hash_including(name: 'Ranking', value: 'brak pozycji'),
      hash_including(name: 'Role', value: 'brak rol rankingowych'),
      hash_including(name: 'Kanaly do pisania', value: 'brak wykrytych kanalow')
    )
  end

  it 'treats missing Discord invites as unavailable and raises typed errors' do
    configuration = PolishOpenSourceRank::Configuration.load
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    capture_http_requests([response('404', 'Not Found', '{}')])

    expect(gateway.invite_available?('used')).to be(false)

    capture_http_requests([response('500', 'Server Error', 'nope')])
    expect { gateway.invite_available?('broken') }.to raise_error(
      PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error
    )

    capture_http_requests([response('500', 'Server Error', 'nope')])
    expect do
      gateway.sync_member(
        discord_user_id: 'discord-1',
        access_token: 'user-token',
        github_login: 'alice',
        desired_role_ids: [],
        managed_role_ids: []
      )
    end.to raise_error(PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error)

    capture_http_requests([response('500', 'Server Error', 'nope')])
    expect do
      gateway.sync_joined_member(
        discord_user_id: 'discord-1',
        github_login: 'alice',
        desired_role_ids: [],
        managed_role_ids: []
      )
    end.to raise_error(PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error)
  end

  it 'counts OAuth and Discord API timeouts before reraising them' do
    configuration = PolishOpenSourceRank::Configuration.load
    github_client = described_class.new(configuration)
    gateway = PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway.new(configuration)
    PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::OAuthHTTP.timeout_count = 0

    allow(Net::HTTP).to receive(:start).and_raise(Net::ReadTimeout)
    expect do
      github_client.exchange_code(code: 'code-1', redirect_uri: 'https://rank/auth/github/callback')
    end.to raise_error(Net::ReadTimeout)

    allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)
    expect do
      gateway.sync_member(
        discord_user_id: 'discord-1',
        access_token: 'user-token',
        github_login: 'alice',
        desired_role_ids: [],
        managed_role_ids: []
      )
    end.to raise_error(Net::OpenTimeout)

    expect(PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::OAuthHTTP.timeout_count).to eq(2)
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
    options = []
    allow(Net::HTTP).to receive(:start) do |_host, _port, **http_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        options << http_options
        responses.shift
      end
      block.call(http)
    end
    [requests, options]
  end

  def json_response(body)
    response('200', 'OK', body)
  end

  def welcome_profile
    {
      login: 'alice',
      name: 'Alice Example',
      html_url: 'https://github.com/alice',
      avatar_url: 'https://avatars.example/alice.png',
      homepage: 'https://alice.example',
      repositories: [
        { full_name: 'alice/app', html_url: 'https://github.com/alice/app', stargazers_count: 12_345 }
      ]
    }
  end

  def welcome_responses
    [
      json_response('[{"id":"role-1","name":"Top 100 PL"},{"id":"other-role","name":"Other"}]'),
      json_response(<<~JSON),
        [
          {"id":"category-1","type":4,"position":0,"name":"ranked","permission_overwrites":[{"id":"role-1","type":0,"allow":"2048","deny":"0"}]},
          {"id":"channel-1","type":0,"position":1,"name":"top-100","parent_id":"category-1","permission_overwrites":[]},
          {"id":"channel-2","type":0,"position":2,"name":"private","permission_overwrites":[{"id":"other-role","type":0,"allow":"2048","deny":"0"}]}
        ]
      JSON
      json_response('{"id":"message-1"}')
    ]
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

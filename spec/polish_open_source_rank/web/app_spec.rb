# frozen_string_literal: true

class FakeGitHubOAuthClient
  attr_reader :exchanged

  def initialize(login, id: 1, location: 'Krakow, Poland')
    @login = login
    @id = id
    @location = location
    @exchanged = []
  end

  def authorize_url(state:, redirect_uri:)
    "https://github.example/oauth?state=#{state}&redirect_uri=#{Rack::Utils.escape(redirect_uri)}"
  end

  def exchange_code(code:, redirect_uri:)
    exchanged << code
    "token-for-#{redirect_uri}"
  end

  def user(_access_token)
    {
      'id' => @id,
      'login' => @login,
      'name' => @login.capitalize,
      'location' => @location,
      'email' => "#{@login}@example.com",
      'homepage' => "https://#{@login}.example",
      'html_url' => "https://github.com/#{@login}",
      'avatar_url' => "https://avatars.example/#{@login}.png"
    }
  end
end

class FakeDiscordOAuthClient
  attr_reader :exchanged

  def initialize
    @exchanged = []
  end

  def authorize_url(state:, redirect_uri:)
    "https://discord.example/oauth?state=#{state}&redirect_uri=#{Rack::Utils.escape(redirect_uri)}"
  end

  def exchange_code(code:, redirect_uri:)
    exchanged << code
    { 'access_token' => 'discord-access', 'redirect_uri' => redirect_uri }
  end

  def user(_access_token)
    { 'id' => 'discord-1', 'username' => 'alice-discord', 'global_name' => 'Alice Discord' }
  end
end

class FakeDiscordGateway
  attr_reader :synced, :welcome

  def invite_available?(_code)
    false
  end

  def create_invite(channel_id:)
    { code: "#{channel_id}-once", url: "https://discord.gg/#{channel_id}-once" }
  end

  def sync_member(**attributes)
    @synced = attributes
  end

  def sync_joined_member(**attributes)
    @synced = attributes
  end

  def post_welcome_message(**attributes)
    @welcome = attributes
  end
end

class FailingDiscordGateway
  def invite_available?(_code)
    raise PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error
  end

  def create_invite(channel_id:)
    raise PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error, channel_id
  end
end

class FailingWelcomeDiscordGateway < FakeDiscordGateway
  def post_welcome_message(**_attributes)
    raise PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error
  end
end

class FailingMemberSyncDiscordGateway < FakeDiscordGateway
  def sync_member(**_attributes)
    raise PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway::Error
  end
end

class FailingDiscordOAuthClient < FakeDiscordOAuthClient
  def exchange_code(code:, redirect_uri:)
    super
    raise PolishOpenSourceRank::Web::Auth::DiscordOAuthClient::Error, '400 invalid_grant'
  end
end

class BrokenDiscordUserClient < FakeDiscordOAuthClient
  def user(_access_token)
    raise StandardError, 'discord user timeout'
  end
end

RSpec.describe PolishOpenSourceRank::Web::App do
  around do |example|
    old_env = ENV.to_h
    old_github_oauth_client = described_class.github_oauth_client
    old_discord_oauth_client = described_class.discord_oauth_client
    old_discord_gateway = described_class.discord_gateway
    ENV['BASE_URL'] = 'https://rank.example'
    ENV.delete('APP_BASE_PATH')
    PolishOpenSourceRank::Web::RateLimiter.reset!
    reset_app_memoized_dependencies
    example.run
  ensure
    PolishOpenSourceRank::Web::RateLimiter.reset!
    ENV.replace(old_env)
    described_class.set :github_oauth_client, old_github_oauth_client
    described_class.set :discord_oauth_client, old_discord_oauth_client
    described_class.set :discord_gateway, old_discord_gateway
    reset_app_memoized_dependencies
  end

  it 'renders the Poland ranking with SEO metadata' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/')

    expect_poland_ranking_page(response)
  end

  it 'renders organization rankings separately' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/organizations')
    shortcut_city_response = Rack::MockRequest.new(described_class).get('/organizations/locations/warszawa')
    latest_city_response = Rack::MockRequest.new(described_class).get('/latest/organizations/locations/warszawa')

    expect_organization_ranking_page(response)
    expect(shortcut_city_response.status).to eq(200)
    expect(latest_city_response.status).to eq(200)
    expect(shortcut_city_response.body).to include(
      'rel="canonical" href="https://rank.example/latest/organizations/locations/warszawa"'
    )
    expect(latest_city_response.body).to include('polish-org/toolkit')
  end

  it 'renders city rankings and empty databases' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    response = Rack::MockRequest.new(described_class).get('/locations/krakow')

    expect(response.status).to eq(200)
    expect(response.body).to include('Kraków')
    expect(response.body).to include('Brak danych rankingowych')
    expect(response.body).to include('Więcej miast')
  end

  it 'renders rankings for completed month slugs' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    latest_response = Rack::MockRequest.new(described_class).get('/latest')
    latest_city_response = Rack::MockRequest.new(described_class).get('/latest/locations/krakow')
    organization_response = Rack::MockRequest.new(described_class).get('/2026-04/organizations')
    organization_city_response = Rack::MockRequest.new(described_class).get('/2026-04/organizations/locations/warszawa')
    response = Rack::MockRequest.new(described_class).get('/2026-04/locations/krakow')
    month_response = Rack::MockRequest.new(described_class).get('/2026-04')

    expect(latest_response.status).to eq(200)
    expect(latest_city_response.status).to eq(200)
    expect(organization_response.status).to eq(200)
    expect(organization_city_response.status).to eq(200)
    expect(response.status).to eq(200)
    expect(month_response.status).to eq(200)
    expect(response.body).to include('alice/app')
    expect_historical_month_page(month_response)
    expect(organization_city_response.body).to include('polish-org/toolkit')
    expect(organization_city_response.body).to include(
      'rel="canonical" href="https://rank.example/2026-04/organizations/locations/warszawa"'
    )
    expect(response.body).to include('rel="canonical" href="https://rank.example/2026-04/locations/krakow"')
  end

  it 'keeps latest pages on the last finished month while the next snapshot is still running' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database_with_running_next_period}"

    latest_response = Rack::MockRequest.new(described_class).get('/latest')
    profile_response = Rack::MockRequest.new(described_class).get('/users/github/alice')
    package_response = Rack::MockRequest.new(described_class).get('/packages/npm')
    running_month_response = Rack::MockRequest.new(described_class).get('/2026-05')

    expect(latest_response.status).to eq(200)
    expect(latest_response.body).to include('datetime="2026-04-01"')
    expect(latest_response.body).to include('alice/app')
    expect(profile_response.body).to include('alice/app')
    expect(package_response.status).to eq(200)
    expect(running_month_response.status).to eq(404)
  end

  it 'renders full top 100 pages for each ranking type', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    responses = ranking_detail_responses

    expect_rankings_detail_pages(responses)
  end

  it 'renders package ranking pages without package profiles', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)
    encoded_name = Base64.urlsafe_encode64('@scope/tool', padding: false)

    responses = package_responses(request, encoded_name)

    expect_package_ranking_pages(responses, encoded_name)
  end

  it 'renders language ranking pages', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    responses = language_responses(request)

    expect_language_ranking_pages(responses)
  end

  it 'renders organization profile pages, organization repository pages, and public organization badges',
     :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    organization_profile = request.get('/organizations/github/polish-org')
    organization_badge = request.get('/badges/organizations/github/polish-org.svg')
    organization_repository = request.get('/organization-repositories/github/polish-org/toolkit')
    missing_organization = request.get('/organizations/github/missing')

    expect(organization_profile.status).to eq(200)
    expect(organization_profile.body).to include('<title>Polish Org - organizacja GitHub</title>')
    expect(organization_profile.body).to include('rel="canonical" href="https://rank.example/organizations/github/polish-org"')
    expect(organization_profile.body).to include('"@type": "Organization"')
    expect(organization_profile.body).to include('Najmocniejsze repozytorium')
    expect(organization_profile.body).to include('Top repozytoria')
    expect(organization_profile.body).to include('Popularne w miesiącu')
    expect(organization_profile.body).to include('Pozycja w Warszawa')
    expect(organization_profile.body).to include('href="/organization-repositories/github/polish-org/toolkit"')
    expect(organization_profile.body).not_to include('Twój dostęp Discord')
    expect(organization_badge.status).to eq(200)
    expect(organization_badge.body).to include('Polish Open Source Org')
    expect(organization_badge.body).to include('1st')
    expect(organization_repository.status).to eq(200)
    expect(organization_repository.body).to include(
      '<title>polish-org/toolkit - repozytorium organizacji na GitHub</title>'
    )
    expect(organization_repository.body).to include('href="/organizations/github/polish-org"')
    expect(organization_repository.body).to include('"@type": "SoftwareSourceCode"')
    expect(organization_repository.body).to include('id="organization-repository-star-history-heading"')
    expect(organization_repository.body).to include('>Historia gwiazdek</h2>')
    expect(organization_repository.body).to include('href="https://www.star-history.com/polish-org/toolkit"')
    expect(organization_repository.body).to include(
      'src="https://api.star-history.com/chart?repos=polish-org%2Ftoolkit&amp;type=date&amp;legend=top-left"'
    )
    expect(missing_organization.status).to eq(404)
  end

  it 'renders organization repository pages for signed-in organization members without a 500' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    described_class.set(
      :github_oauth_client,
      FakeGitHubOAuthClient.new('polish-org', id: 30, location: 'Poznan, Poland')
    )
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    response = request.get(
      '/organization-repositories/github/polish-org/toolkit',
      'HTTP_COOKIE' => cookie_header(github_callback)
    )

    expect(response.status).to eq(200)
    expect(response.body).to include('polish-org/toolkit')
  end

  it 'renders user profile pages from ranking users', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    ranking_response = request.get('/latest/users/top')
    profile_response = request.get('/users/github/alice')
    badge_response = request.get('/badges/users/github/alice.svg')
    missing_response = request.get('/users/github/missing')

    expect_user_profile_page(
      ranking_response: ranking_response,
      profile_response: profile_response,
      badge_response: badge_response,
      missing_response: missing_response
    )
  end

  it 'logs public GitHub users in and syncs their Discord account', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'invite-channel'
    ENV['DISCORD_GUILD_ID'] = 'guild-1'
    ENV['DISCORD_ROLE_TOP_100_PL'] = 'role-top-100'
    ENV['DISCORD_ROLE_TOP_100_CITY_KRAKOW'] = 'role-krakow'
    ENV['DISCORD_ROLE_BADGE_TOP_1'] = 'role-gold'
    github_client = FakeGitHubOAuthClient.new('alice')
    discord_client = FakeDiscordOAuthClient.new
    discord_gateway = FakeDiscordGateway.new
    described_class.set :github_oauth_client, github_client
    described_class.set :discord_oauth_client, discord_client
    described_class.set :discord_gateway, discord_gateway
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect_signed_in_profile(github_callback, profile)

    discord_callback = finish_discord_auth(request, github_callback)

    expect_queued_discord_sync(request, discord_callback)
    expect(github_client.exchanged).to eq(['github-code'])
    expect(discord_client.exchanged).to eq(['discord-code'])
  end

  it 'creates a public profile for GitHub users with a supported location' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    github_client = FakeGitHubOAuthClient.new('outsider', id: 40, location: 'Poznan, Poland')
    described_class.set :github_oauth_client, github_client
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    profile = request.get('/users/github/outsider', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(github_callback.location).to eq('http://example.org/users/github/outsider')
    expect(profile.status).to eq(200)
    expect(profile.body).to include('Poznan, Poland')
    expect(profile.body).to include('Polish Open Source')
    expect(profile.body).to include('Poza rankingiem.')
    expect(profile.body).to include('Profil w rankingu')
    expect(profile.body).to include('>-<')
  end

  it 'keeps users signed out when their GitHub location is not eligible' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    github_client = FakeGitHubOAuthClient.new('outsider', id: 40, location: 'Berlin, Germany')
    described_class.set :github_oauth_client, github_client
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    rankings = request.get('/latest', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(github_callback.location).to eq('http://example.org/latest')
    expect(rankings.body.force_encoding('UTF-8')).to include('Przepraszamy, nie ma cię w naszej bazie.')
    expect(rankings.body).not_to include('href="/users/github/outsider"')
  end

  it 'returns to the profile after Discord sync when the server channel is not configured' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['DISCORD_GUILD_ID'] = ''
    ENV['DISCORD_INVITE_CHANNEL_ID'] = ''
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    described_class.set :discord_oauth_client, FakeDiscordOAuthClient.new
    described_class.set :discord_gateway, FakeDiscordGateway.new
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )

    expect(discord_callback.location).to eq('http://example.org/users/github/alice')
  end

  it 'does not fail Discord login when the welcome message cannot be posted' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'invite-channel'
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    described_class.set :discord_oauth_client, FakeDiscordOAuthClient.new
    described_class.set :discord_gateway, FailingWelcomeDiscordGateway.new
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )

    expect(discord_callback.status).to eq(302)
  end

  it 'returns to the profile with a retry message when Discord rejects the OAuth callback' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    without_discord_channel_env!
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    described_class.set :discord_oauth_client, FailingDiscordOAuthClient.new
    described_class.set :discord_gateway, FakeDiscordGateway.new
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )
    profile = request.get(discord_callback.location, 'HTTP_COOKIE' => cookie_header(discord_callback))

    expect(discord_callback.status).to eq(302)
    expect(discord_callback.location).to eq('http://example.org/users/github/alice')
    expect(profile.body).to include('Discord odrzucił logowanie')
  end

  it 'returns to the profile with a retry message when Discord user loading fails' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    without_discord_channel_env!
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    described_class.set :discord_oauth_client, BrokenDiscordUserClient.new
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )
    profile = request.get(discord_callback.location, 'HTTP_COOKIE' => cookie_header(discord_callback))

    expect(discord_callback.location).to eq('http://example.org/users/github/alice')
    expect(profile.body).to include('Nie udało się zsynchronizować konta Discord')
  end

  it 'queues Discord member sync without waiting for the gateway' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['DISCORD_GUILD_ID'] = '1505949566229286972'
    ENV['DISCORD_INVITE_CHANNEL_ID'] = '1505949566699176050'
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    described_class.set :discord_oauth_client, FakeDiscordOAuthClient.new
    described_class.set :discord_gateway, FailingMemberSyncDiscordGateway.new
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(discord_callback))

    expect(discord_callback.status).to eq(302)
    expect(discord_callback.location).to eq('https://discord.com/channels/1505949566229286972/1505949566699176050')
    expect(profile.body).to include('Synchronizacja Discord jest w kolejce')
  end

  it 'rejects Discord sync when the logged-in GitHub profile is no longer ranked' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    without_discord_channel_env!
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    discord_client = FakeDiscordOAuthClient.new
    allow(discord_client).to receive(:user).and_raise(
      PolishOpenSourceRank::Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
    )
    described_class.set :discord_oauth_client, discord_client
    described_class.set :discord_gateway, FakeDiscordGateway.new
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)

    expect(finish_discord_auth(request, github_callback).status).to eq(404)
  end

  it 'logs out and keeps the Discord panel useful without creating invites' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    github_client = FakeGitHubOAuthClient.new('alice')
    described_class.set :github_oauth_client, github_client
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(github_callback))
    session_cookie = cookie_header(profile)
    invalid_logout = request.post('/logout', 'HTTP_COOKIE' => session_cookie)
    logout = request.post(
      '/logout',
      'HTTP_COOKIE' => session_cookie,
      'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
      input: Rack::Utils.build_query(csrf_token: csrf_token_from(profile))
    )

    expect(profile.body).to include('Dołącz do Elite Discorda')
    expect(profile.body).to include('Dostępne grupy')
    expect(profile.body).to include('Ruby')
    expect(profile.body).to include('Top 100 Ruby')
    expect(profile.body).to include('/auth/discord')
    expect(profile.body).to include('name="csrf_token"')
    expect(invalid_logout.status).to eq(403)
    expect(logout.status).to eq(303)
    expect(logout.location).to eq('http://example.org/latest')
  end

  it 'lets signed-in users delete their public profile page without changing ranking order', :aggregate_failures do
    database_path = seed_database
    ENV['DATABASE_URL'] = "sqlite://#{database_path}"
    ENV['PUBLIC_DATABASE_URL'] = ''
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    session_cookie = cookie_header(github_callback)
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => session_cookie)
    profile_cookie = cookie_header(profile)
    invalid_delete = request.post('/users/github/alice/delete', 'HTTP_COOKIE' => profile_cookie)
    delete = request.post(
      '/users/github/alice/delete',
      'HTTP_COOKIE' => profile_cookie,
      'CONTENT_TYPE' => 'application/x-www-form-urlencoded',
      input: Rack::Utils.build_query(csrf_token: csrf_token_from(profile))
    )
    deleted_profile = request.get('/users/github/alice', 'HTTP_COOKIE' => profile_cookie)
    ranking = request.get('/latest/users/top')
    user = bootstrapped_database(database_path).dataset(:users).where(platform: 'github', login: 'alice').first

    expect(profile.body).to include('Chcesz usunąć tę stronę z bazy danych? Kliknij')
    expect(profile.body).to include('Czy na pewno chcesz usunąć twój profil z bazy danych?')
    expect(invalid_delete.status).to eq(403)
    expect(delete.status).to eq(303)
    expect(delete.location).to eq('http://example.org/users/github/alice')
    expect(user).to include(profile_deleted: 1, name: nil, avatar_url: nil, avatar_hidden: 1)
    expect(deleted_profile.body).to include('Profil usunięty')
    expect(deleted_profile.body).to include('Usunięte')
    expect(deleted_profile.body).not_to include('src="https://avatars.example/alice.png"')
    expect(deleted_profile.body).not_to include('Profil na GitHub')
    expect(deleted_profile.body).not_to include('href="/repositories/github/alice/app"')
    expect(ranking.body).to include('<span class="primary-link primary-link--static">alice</span>')
    expect(ranking.body).to include('href="https://github.com/alice"')
    expect(ranking.body).not_to include('href="/users/github/alice"')
  end

  it 'rejects replayed GitHub OAuth callback states' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    callback_path = "/auth/github/callback?code=github-code&state=#{github_state}"
    github_callback = request.get(callback_path, 'HTTP_COOKIE' => cookie_header(github_start))
    replay = request.get(callback_path, 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(github_callback.status).to eq(302)
    expect(replay.status).to eq(400)
  end

  it 'keeps podium medals on profile pages', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    expect(request.get('/users/github/alice').body).to include('/icons/medal-gold.svg')
    expect(request.get('/users/github/bob').body).to include('/icons/medal-silver.svg')
    expect(request.get('/users/github/carol').body).to include('/icons/medal-bronze.svg')
  end

  it 'renders repository profile pages and GitHub badges from ranking projects', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    ranking_response = request.get('/latest/repositories/top')
    profile_response = request.get('/repositories/github/alice/app')
    badge_response = request.get('/badges/repositories/github/alice/app.svg')
    short_badge_response = request.get('/badges/repositories/alice/app.svg')
    missing_response = request.get('/repositories/github/alice/missing')
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    owner_profile_response = request.get(
      '/repositories/github/alice/app',
      'HTTP_COOKIE' => cookie_header(github_callback)
    )

    expect_repository_profile_page(
      ranking_response: ranking_response,
      profile_response: profile_response,
      owner_profile_response: owner_profile_response,
      badge_response: badge_response,
      short_badge_response: short_badge_response,
      missing_response: missing_response
    )
  end

  it 'renders editions with year pagination' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/editions')

    expect_editions_page(response)
  end

  it 'renders edition archive year pages and missing years' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    year_response = Rack::MockRequest.new(described_class).get('/editions/2025')
    invalid_response = Rack::MockRequest.new(described_class).get('/editions/2024')

    expect(year_response.status).to eq(200)
    expect(year_response.body).to include('grudzień 2025')
    expect(year_response.body).to include('href="/editions/2026"')
    expect(invalid_response.status).to eq(404)
  end

  it 'renders the about page' do
    response = Rack::MockRequest.new(described_class).get('/about')

    expect_about_page(response)
  end

  it 'keeps core public pages semantically structured', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    rankings = request.get('/latest')
    about = request.get('/about')
    profile = request.get('/users/github/alice')

    expect(html_elements(rankings.body, '//h1').length).to eq(1)
    expect(html_elements(about.body, '//h1').length).to eq(1)
    expect(html_elements(profile.body, '//h1').length).to eq(1)
    expect(html_element(rankings.body, "//*[@id='main-content']")).not_to be_nil
    expect(html_element(rankings.body, "//*[@role='navigation' and @aria-label='Język']")).not_to be_nil
    expect(
      html_element(rankings.body, "//img[@src='/icons/polish-open-source.png' and @alt='' and @aria-hidden='true']")
    ).not_to be_nil
    expect(
      html_element(
        rankings.body,
        "//img[@src='/images/polish_open_source_front.webp' and @alt='' and @aria-hidden='true']"
      )
    ).not_to be_nil
    expect(html_element(rankings.body, "//article[@class='ranking-table' and @aria-labelledby='ranking-users-top']"))
      .not_to be_nil
  end

  it 'links about platform cards to source platforms' do
    response = Rack::MockRequest.new(described_class).get('/about')

    expect(response.body).to include('href="https://github.com/"')
    expect(response.body).to include('href="https://gitlab.com/"')
    expect(response.body).to include('href="https://codeberg.org/"')
  end

  it 'uses SVG platform icons instead of text markers' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    ranking_response = Rack::MockRequest.new(described_class).get('/')
    about_response = Rack::MockRequest.new(described_class).get('/about')

    expect(ranking_response.body).to include('src="/icons/github.svg"')
    expect(ranking_response.body).not_to include('>GH</span>')
    expect(about_response.body).to include('src="/icons/gitlab.svg"')
    expect(about_response.body).to include('src="/icons/codeberg.svg"')
    expect(about_response.body).not_to include('Publiczne profile, projekty')
  end

  it 'renders Polish content when requested by accepted language' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    polish_response = request.get('/', 'HTTP_ACCEPT_LANGUAGE' => 'pl-PL,pl;q=0.9')

    expect(polish_response.body).to include('<html lang="pl">')
    expect(polish_response.body).to include('aria-label="Język"')
    expect(polish_response.body).to include('Ludzie')
    expect(polish_response.body).to include('Zobacz top 100')
    expect(polish_response.body).to include('href="/en"')
  end

  it 'renders English content by explicit locale and keeps explicit locale pages cookie-free' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    english_response = request.get('/en/latest')
    cookie_response = request.get('/latest', 'HTTP_COOKIE' => 'locale=en')

    expect_english_locale_page(english_response)
    expect(english_response['Set-Cookie']).to be_nil
    expect(cookie_response.status).to eq(302)
    expect(cookie_response.location).to eq('http://example.org/en/latest')
  end

  it 'redirects locale query params to stable localized URLs and stores the selected locale' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    english_redirect = request.get('/latest?lang=en')
    polish_redirect = request.get('/en/latest?lang=pl', 'HTTP_COOKIE' => 'locale=en')
    prefixed_polish_redirect = request.get('/pl/latest', 'HTTP_COOKIE' => 'locale=en')

    expect(english_redirect.status).to eq(302)
    expect(english_redirect.location).to eq('http://example.org/en/latest')
    expect_locale_cookie(english_redirect, 'locale=en')

    expect(polish_redirect.status).to eq(302)
    expect(polish_redirect.location).to eq('http://example.org/latest')
    expect_locale_cookie(polish_redirect, 'locale=pl')

    expect(prefixed_polish_redirect.status).to eq(302)
    expect(prefixed_polish_redirect.location).to eq('http://example.org/latest')
    expect_locale_cookie(prefixed_polish_redirect, 'locale=pl')
  end

  it 'keeps signed-in navigation on the selected English locale' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    request = Rack::MockRequest.new(described_class)

    github_callback = sign_in_with_github(request)
    english_redirect = request.get('/latest?lang=en', 'HTTP_COOKIE' => cookie_header(github_callback))
    english_cookie = cookie_header(github_callback, english_redirect)
    english_latest = request.get('/en/latest', 'HTTP_COOKIE' => english_cookie)
    english_about = request.get('/en/about', 'HTTP_COOKIE' => english_cookie)
    english_profile = request.get('/en/users/github/alice', 'HTTP_COOKIE' => english_cookie)

    expect(english_redirect.location).to eq('http://example.org/en/latest')
    expect(english_latest.body).to include('<html lang="en">')
    expect(english_latest.body).to include('href="/en/about"')
    expect(english_latest.body).to include('href="/en/users/github/alice"')
    expect(english_about.body).to include('<html lang="en">')
    expect(english_profile.body).to include('<html lang="en">')
  end

  it 'renders links and assets under a configured app base path' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['BASE_URL'] = 'https://rank.example'
    ENV['APP_BASE_PATH'] = '/'

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.body).to include('rel="canonical" href="https://rank.example/"')
    expect(response.body).to match(%r{href="/css/application\.css\?v=\d+"})
    expect(response.body).to match(%r{href="/css/components/navigation\.css\?v=\d+"})
    expect(response.body).to match(%r{href="/css/responsive\.css\?v=\d+"})
    expect(response.body).to match(%r{src="/js/navigation\.js\?v=\d+"})
    expect(response.body).to include('src="/icons/github.svg"')
    expect(response.body).to include('href="/latest/locations/krakow"')
    expect(response.body).to include('href="/latest/users/top"')
    expect(response.body).to include('href="/editions"')
    expect(response.body).to include('href="/about"')
  end

  it 'uses conditional cache headers for public pages and badges', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    response = request.get('/latest')
    head_response = request.head('/latest')
    not_modified = request.get('/latest', 'HTTP_IF_NONE_MATCH' => response['ETag'])
    badge_response = request.get('/badges/users/github/alice.svg')
    badge_not_modified = request.get('/badges/users/github/alice.svg', 'HTTP_IF_NONE_MATCH' => badge_response['ETag'])
    missing_badge = request.get('/badges/users/github/missing.svg')

    expect(response['Cache-Control']).to eq(
      'public, max-age=60, stale-while-revalidate=300, stale-if-error=86400'
    )
    expect(response['ETag']).to match(/\A".+"\z/)
    expect(response['Vary']).to include('Cookie')
    expect(head_response['Set-Cookie']).to be_nil
    expect(not_modified.status).to eq(304)
    expect(badge_response['Cache-Control']).to eq(
      'public, max-age=3600, stale-while-revalidate=86400, stale-if-error=86400'
    )
    expect(badge_response['ETag']).to match(/\A".+"\z/)
    expect(badge_response['Vary'].to_s).not_to include('Cookie')
    expect(badge_not_modified.status).to eq(304)
    expect(missing_badge['Cache-Control']).to be_nil
  end

  it 'short-caches safe public 404 responses without caching data-dependent misses', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    invalid_ranking = request.get('/latest/locations/not-a-city')
    unsupported_package_metric = request.get('/latest/packages/nuget/top')
    missing_profile = request.get('/users/github/missing')

    expect(invalid_ranking.status).to eq(404)
    expect(invalid_ranking['Cache-Control']).to eq(
      'public, max-age=30, stale-while-revalidate=120, stale-if-error=300'
    )
    expect(invalid_ranking['ETag']).to match(/\A".+"\z/)
    expect(invalid_ranking['Vary']).to include('Cookie')
    expect(unsupported_package_metric.status).to eq(404)
    expect(unsupported_package_metric['Cache-Control']).to eq(
      'public, max-age=30, stale-while-revalidate=120, stale-if-error=300'
    )
    expect(unsupported_package_metric['Vary']).to include('Cookie')
    expect(missing_profile.status).to eq(404)
    expect(missing_profile['Cache-Control']).to be_nil
  end

  it 'keeps public cache separate from private session responses', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    signed_in_latest = request.get('/latest', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(signed_in_latest['Cache-Control']).to eq('private, no-cache')
    expect(signed_in_latest['Vary']).to include('Cookie')
  end

  it 'rate limits abusive operational and auth paths without limiting normal public pages', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    request = Rack::MockRequest.new(described_class)

    30.times { expect(request.get('/auth/github').status).to eq(302) }
    limited = request.get('/auth/github')
    public_page = request.get('/latest')

    expect(limited.status).to eq(429)
    expect(limited['Cache-Control']).to eq('no-store')
    expect(limited['Retry-After']).to match(/\A\d+\z/)
    expect(public_page.status).to eq(200)
  end

  it 'compresses public HTML and badge responses when clients support gzip', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    html = request.get('/latest', 'HTTP_ACCEPT_ENCODING' => 'gzip')
    badge = request.get('/badges/users/github/alice.svg', 'HTTP_ACCEPT_ENCODING' => 'gzip')

    expect(html['Content-Encoding']).to eq('gzip')
    expect(badge['Content-Encoding']).to eq('gzip')
  end

  it 'serves static assets with immutable cache headers', :aggregate_failures do
    response = Rack::MockRequest.new(described_class).get('/css/application.css')

    expect(response.status).to eq(200)
    expect(response['Cache-Control']).to include('max-age=31536000')
    expect(response['Cache-Control']).to include('immutable')
  end

  it 'keeps session-specific and internal pages out of shared caches', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(github_callback))
    internal = request.get('/internal/jobs', internal_auth_env)

    expect(github_start['Cache-Control']).to eq('no-store')
    expect(profile['Cache-Control']).to eq('private, no-cache')
    expect(internal['Cache-Control']).to eq('no-store')
  end

  it 'adds security headers to public, auth, badge, and internal responses', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"
    described_class.set :github_oauth_client, FakeGitHubOAuthClient.new('alice')
    request = Rack::MockRequest.new(described_class)

    responses = [
      request.get('/latest'),
      request.get('/auth/github'),
      request.get('/badges/users/github/alice.svg'),
      request.get('/internal/jobs', internal_auth_env)
    ]

    responses.each do |response|
      expect(response['Content-Security-Policy']).to include("default-src 'self'")
      expect(response['Content-Security-Policy']).to include("frame-ancestors 'none'")
      expect(response['Content-Security-Policy']).not_to include("'unsafe-inline'")
      expect(response['X-Content-Type-Options']).to eq('nosniff')
      expect(response['Strict-Transport-Security']).to eq('max-age=31536000; includeSubDomains')
      expect(response['Referrer-Policy']).to eq('strict-origin-when-cross-origin')
      expect(response['Permissions-Policy']).to include('camera=()')
    end
  end

  it 'requires application Basic Auth for internal operation pages', :aggregate_failures do
    request = Rack::MockRequest.new(described_class)

    unauthenticated = request.get('/internal/jobs')
    wrong_password = request.get(
      '/internal/jobs',
      internal_auth_env(password: 'wrong-internal-password')
    )

    expect(unauthenticated.status).to eq(401)
    expect(wrong_password.status).to eq(401)
    expect(unauthenticated['WWW-Authenticate']).to eq(
      'Basic realm="Polish Open Source operations", charset="UTF-8"'
    )
    expect(unauthenticated['Cache-Control']).to eq('no-store')
    expect(unauthenticated['Content-Security-Policy']).to include("default-src 'self'")
  end

  it 'marks every external target blank link as opener-safe', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    html = Rack::MockRequest.new(described_class).get('/latest').body
    target_blank_links = html.scan(/<a\b[^>]*target="_blank"[^>]*>/)

    expect(target_blank_links).not_to be_empty
    expect(target_blank_links).to all(include('rel="noopener noreferrer"'))
  end

  it 'does not render unsafe external URLs from public data as href or src attributes', :aggregate_failures do
    path = seed_database
    ENV['DATABASE_URL'] = "sqlite://#{path}"
    poison_public_urls(path)

    request = Rack::MockRequest.new(described_class)
    html = [
      request.get('/latest').body,
      request.get('/users/github/alice').body,
      request.get('/repositories/github/alice/app').body,
      request.get('/latest/packages/npm/top').body
    ].join("\n")

    expect(html).not_to include('href="javascript:')
    expect(html).not_to include('href="data:')
    expect(html).not_to include('href="ftp:')
    expect(html).not_to include('src="https://user:password@')
  end

  it 'serves health checks and 404 pages' do
    ENV['DATABASE_URL'] = "sqlite://#{empty_database}"

    expect(Rack::MockRequest.new(described_class).get('/healthz').body).to eq('ok')
    expect(Rack::MockRequest.new(described_class).get('/locations/unknown').status).to eq(404)
    expect(Rack::MockRequest.new(described_class).get('/2026-13').status).to eq(404)
  end

  it 'serves robots.txt and sitemap.xml for crawlers', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    robots = request.get('/robots.txt')
    sitemap = request.get('/sitemap.xml')

    expect(robots.status).to eq(200)
    expect(robots.content_type).to include('text/plain')
    expect(robots.body).to include('Disallow: /internal/')
    expect(robots.body).to include('Sitemap: https://rank.example/sitemap.xml')
    expect(sitemap.status).to eq(200)
    expect(sitemap.content_type).to include('application/xml')
    sitemap_locations = REXML::XPath.match(xml_document(sitemap.body), '//url/loc').map(&:text)
    expect(sitemap_locations).to include('https://rank.example/')
    expect(sitemap_locations).to include('https://rank.example/latest/organizations')
    expect(sitemap_locations).to include('https://rank.example/latest/organizations/active')
    expect(sitemap_locations).to include('https://rank.example/latest/organizations/locations/krakow')
    expect(sitemap_locations).to include('https://rank.example/en')
    expect(sitemap_locations).not_to include('https://rank.example/latest')
    expect(sitemap_locations).not_to include('https://rank.example/en/latest')
    expect(sitemap_locations).to include('https://rank.example/about')
    expect(sitemap_locations).to include('https://rank.example/en/users/github/alice')
    expect(sitemap_locations).to include('https://rank.example/en/organizations/github/polish-org')
    expect(sitemap_locations).to include('https://rank.example/en/organization-repositories/github/polish-org/toolkit')
    expect(sitemap_locations).to include('https://rank.example/latest/locations/krakow/organizations/top')
    expect(sitemap_locations).to include('https://rank.example/packages')
    expect(sitemap_locations).to include('https://rank.example/en/latest/packages/npm/top')
    expect(sitemap_locations).not_to include('https://rank.example/internal/jobs')
    expect(REXML::XPath.match(xml_document(sitemap.body), '//url/lastmod')).not_to be_empty
  end

  it 'splits oversized sitemaps into a sitemap index', :aggregate_failures do
    stub_const('PolishOpenSourceRank::Web::Controllers::SitemapSupport::SITEMAP_URL_LIMIT', 5)
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    sitemap_index = request.get('/sitemap.xml')
    first_sitemap = request.get('/sitemaps/1.xml')
    missing_sitemap = request.get('/sitemaps/999.xml')

    index_locations = REXML::XPath.match(xml_document(sitemap_index.body), '//sitemap/loc').map(&:text)
    page_locations = REXML::XPath.match(xml_document(first_sitemap.body), '//url/loc').map(&:text)

    expect(sitemap_index.status).to eq(200)
    expect(index_locations).to include('https://rank.example/sitemaps/1.xml')
    expect(first_sitemap.status).to eq(200)
    expect(page_locations.size).to eq(5)
    expect(page_locations).to include('https://rank.example/')
    expect(missing_sitemap.status).to eq(404)
  end

  it 'keeps localized metadata consistent across key public pages', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    about = request.get('/about')
    editions = request.get('/editions')
    user_profile = request.get('/users/github/alice')
    repository_profile = request.get('/repositories/github/alice/app')
    english_about = request.get('/en/about')

    expect(about.body).to include('<html lang="pl">')
    expect(about.body).to include('rel="canonical" href="https://rank.example/about"')
    expect(about.body).to include('rel="alternate" hreflang="en" href="https://rank.example/en/about"')
    expect(about.body).to include('property="og:title" content="O Polish Open Source"')
    expect(about.body).to include('name="twitter:card" content="summary_large_image"')

    expect(editions.body).to include('rel="canonical" href="https://rank.example/editions"')
    expect(editions.body).to include('property="og:image" content="https://rank.example/images/polish_open_source_front.webp"')

    expect(user_profile.body).to include('rel="canonical" href="https://rank.example/users/github/alice"')
    expect(user_profile.body).to include('property="og:type" content="profile"')
    expect(user_profile.body).to include('name="twitter:image" content="https://rank.example/images/polish_open_source_front.webp"')

    expect(repository_profile.body).to include('rel="canonical" href="https://rank.example/repositories/github/alice/app"')
    expect(repository_profile.body).to include('name="twitter:image" content="https://rank.example/images/polish_open_source_front.webp"')

    expect(english_about.body).to include('<html lang="en">')
    expect(english_about.body).to include('rel="canonical" href="https://rank.example/en/about"')
    expect(english_about.body).to include('property="og:locale" content="en_US"')
    expect(english_about.body).to include('Back to top')
    expect(english_about.body).to include('Data sources')
  end

  it 'serves internal job progress as a noindex monitor page', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    response = Rack::MockRequest.new(described_class).get('/internal/jobs', internal_auth_env)

    expect(response.status).to eq(200)
    expect(response.content_type).to include('text/html')
    expect(response['X-Robots-Tag']).to eq('noindex, nofollow, noarchive')
    expect(response.body).to include('<title>Job monitor</title>')
    expect(response.body).to include('noindex,nofollow,noarchive')
    expect(response.body).to include('2026-04-01 to 2026-05-01')
    expect(response.body).to include('CEST')
    expect(response.body).to include('Independent job stages')
    expect(response.body).to include('user repositories / github')
    expect(response.body).to include('State')
    expect(response.body).to include('Throughput/min')
    expect(response.body).to include('Median')
    expect(response.body).to include('p95')
    expect(response.body).to include('ETA avg')
    expect(response.body).to include('ETA p95')
    expect(response.body).to include('Status detail')
    expect(response.body).to include('Last event')
    expect(response.body).to include('Last monitor events')
    expect(response.body).to include('Last error logs')
    expect(response.body).to include('monitor-table')
  end

  def seed_database
    path = empty_database
    database = bootstrapped_database(path)
    run_repository = snapshot_run_repository(database)
    snapshot_repository = snapshot_repository(database)
    older_period = PolishOpenSourceRank::Shared::Domain::Period.parse('2025-12')
    seed_period(run_repository, snapshot_repository, older_period)

    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    seed_period(run_repository, snapshot_repository, period)
    seed_package_records(database, older_period)
    seed_package_records(database, period)
    path
  end

  def seed_database_with_running_next_period
    path = seed_database
    database = bootstrapped_database(path)
    run_repository = snapshot_run_repository(database)
    snapshot_repository = snapshot_repository(database)
    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-05')
    run_repository.create(period)
    snapshot_repository.record_user_stats(user_stats(period))
    snapshot_repository.record_repository_stats(repository_stats(period))
    path
  end

  def poison_public_urls(path)
    database = bootstrapped_database(path)
    database.execute(
      'UPDATE users SET html_url = ?, homepage = ?, avatar_url = ? WHERE login = ?',
      ['javascript:alert(1)', 'data:text/html,<script>alert(1)</script>', 'https://user:password@example.test/a.png',
       'alice']
    )
    database.execute(
      'UPDATE repositories SET html_url = ?, homepage = ? WHERE full_name = ?',
      ['javascript:alert(1)', 'ftp://example.test/repo', 'alice/app']
    )
    database.execute(
      'UPDATE registry_packages SET registry_url = ?, repository_url = ? WHERE ecosystem = ?',
      ['javascript:alert(1)', 'data:text/html,<script>alert(1)</script>', 'npm']
    )
  end

  def seed_period(run_repository, snapshot_repository, period)
    run_id = run_repository.create(period)
    snapshot_repository.upsert_user(user_attributes)
    snapshot_repository.record_user_stats(user_stats(period))
    snapshot_repository.upsert_repository(repository_attributes)
    snapshot_repository.record_repository_stats(repository_stats(period))
    snapshot_repository.record_organization_snapshot(organization_snapshot(period))
    snapshot_repository.record_organization_repository_snapshot(organization_repository_snapshot(period))
    seed_extra_ranked_records(snapshot_repository, period)
    run_repository.finish(run_id)
  end

  def ranking_detail_responses
    request = Rack::MockRequest.new(described_class)

    {
      user: request.get('/2026-04/locations/krakow/users/active'),
      repository: request.get('/2026-04/repositories/trending'),
      organization: request.get('/2026-04/organizations/top'),
      organization_active: request.get('/2026-04/organizations/active'),
      organization_repository: request.get('/2026-04/organization-repositories/trending'),
      latest_user: request.get('/latest/users/top'),
      latest_city_repository: request.get('/latest/locations/krakow/repositories/top'),
      city_organization: request.get('/2026-04/locations/warszawa/organizations/top'),
      invalid_repository: request.get('/2026-04/repositories/active'),
      invalid_city_organization: request.get('/2026-04/locations/unknown/organizations/top')
    }
  end

  def package_responses(request, encoded_name)
    {
      index: request.get('/packages'),
      ecosystem: request.get('/latest/packages/npm'),
      shortcut: request.get('/packages/npm'),
      period_ecosystem: request.get('/2026-04/packages/npm'),
      top: request.get('/latest/packages/npm/top'),
      user_top: request.get('/latest/packages/npm/users/top'),
      period_user_top: request.get('/2026-04/packages/npm/users/top'),
      downloads: request.get('/2026-04/packages/npm/downloads'),
      dependents: request.get('/latest/packages/npm/dependents'),
      rubygems: request.get('/latest/packages/rubygems'),
      rubygems_dependents: request.get('/latest/packages/rubygems/dependents'),
      homebrew: request.get('/latest/packages/homebrew'),
      homebrew_top: request.get('/latest/packages/homebrew/top'),
      nuget: request.get('/latest/packages/nuget'),
      nuget_downloads: request.get('/latest/packages/nuget/downloads'),
      package_profile: request.get("/packages/npm/names/#{encoded_name}"),
      missing_profile: request.get('/packages/npm/names/not-base64!')
    }
  end

  def language_responses(request)
    {
      index: request.get('/languages'),
      language: request.get('/latest/languages/Ruby'),
      period_language: request.get('/2026-04/languages/Ruby'),
      language_all_top: request.get('/latest/languages/Ruby/repositories/top'),
      language_user_top: request.get('/latest/languages/Ruby/users/top'),
      language_organization_top: request.get('/2026-04/languages/Ruby/organizations/top'),
      top: request.get('/latest/languages/top'),
      stars: request.get('/2026-04/languages/stars'),
      trending: request.get('/latest/languages/trending'),
      invalid: request.get('/latest/languages/downloads')
    }
  end

  def expect_language_ranking_pages(responses)
    expect_language_index_page(responses.fetch(:index))
    expect_language_repository_pages(responses)
    expect_language_detail_pages(responses)
    expect(responses.fetch(:invalid).status).to eq(404)
  end

  def expect_language_index_page(response)
    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Języki open source - Polish Open Source</title>')
    expect(response.body).to include('Ruby')
    expect(response.body).to include('<dd>⭐ 31 110</dd>')
    expect(response.body).to include('href="/latest/languages/Ruby"')
    expect(response.body).to include('Zobacz ranking')
    expect(response.body).not_to include('index-card__repository')
    expect(response.body).not_to include('michalsnik/aos')
    expect(response.body).not_to include('00Baarti/Strona-QUIZ')
  end

  def expect_language_repository_pages(responses)
    expect_language_page(responses.fetch(:language))
    expect_period_language_page(responses.fetch(:period_language))
    expect_language_repository_detail_pages(responses)
  end

  def expect_language_page(response)
    expect(response.body).to include('<h1>Ruby</h1>')
    expect(response.body).to include('Wszystkie repozytoria')
    expect(response.body).to include('Repozytoria ludzi')
    expect(response.body).to include('Repozytoria organizacji')
    expect(response.body).to include('Top 10 według gwiazdek')
    expect(response.body).to include('Top 10 popularnych w miesiącu')
    expect(response.body).to include('⭐ 12 345')
    expect(response.body).to include('alice/app')
    expect(response.body).to include('Nice Ruby app')
    expect(response.body).to include('polish-org/toolkit')
    expect(response.body).to include('Shared tooling')
    expect(response.body).to include('href="/latest/languages/Ruby/repositories/top"')
    expect(response.body).to include('href="/latest/languages/Ruby/users/top"')
    expect(
      html_element(response.body, "//li[.//a[text()='alice/app']]//span[contains(@class, 'ranking-list__links')]" \
                                  "/a[@href='https://github.com/alice/app' and text()='GitHub']")
    ).not_to be_nil
  end

  def expect_period_language_page(response)
    expect(response.body).to include('rel="canonical" href="https://rank.example/2026-04/languages/Ruby"')
  end

  def expect_language_repository_detail_pages(responses)
    expect(responses.fetch(:language_all_top).body).to include(
      'Top 100: Wszystkie repozytoria, Ruby, według gwiazdek'
    )
    expect(responses.fetch(:language_all_top).body).to include('alice/app')
    expect(responses.fetch(:language_all_top).body).to include('polish-org/toolkit')
    expect(responses.fetch(:language_user_top).body).to include('Top 100: Repozytoria ludzi, Ruby, według gwiazdek')
    expect(responses.fetch(:language_user_top).body).to include('alice/app')
    expect(responses.fetch(:language_user_top).body).to include('Nice Ruby app')
    expect(
      html_element(
        responses.fetch(:language_user_top).body,
        "//ol[@class='ranking-list' and @aria-labelledby='language-repository-ranking-detail-user-top']"
      )
    ).not_to be_nil
    expect(responses.fetch(:language_organization_top).body).to include('polish-org/toolkit')
    expect(responses.fetch(:language_organization_top).body).to include('Shared tooling')
  end

  def expect_language_detail_pages(responses)
    expect(responses.fetch(:top).body).to include('Top 100 języków według liczby repozytoriów')
    expect(responses.fetch(:stars).body).to include('Top 100 języków według gwiazdek')
    expect(responses.fetch(:trending).body).to include('Top 100 popularnych języków')
  end

  def expect_package_ranking_pages(responses, encoded_name)
    expect_package_index_page(responses.fetch(:index))
    expect_package_ecosystem_page(responses.fetch(:ecosystem), encoded_name)
    expect_package_detail_pages(responses)
    expect(responses.fetch(:package_profile).status).to eq(404)
    expect(responses.fetch(:missing_profile).status).to eq(404)
  end

  def expect_package_ecosystem_page(response, encoded_name)
    expect(response.status).to eq(200)
    expect(response.body).to include('@scope/tool')
    expect(response.body).to include('<span class="ranking-list__title-meta"> - alice</span>')
    expect(response.body).not_to include("href=\"/packages/npm/names/#{encoded_name}\"")
    expect(response.body).to include('href="https://www.npmjs.com/package/@scope/tool"')
    expect_package_registry_and_repository_links(response)
    expect(response.body).to include('Wszystkie repozytoria')
    expect(response.body).to include('Repozytoria ludzi')
    expect(response.body).to include('Repozytoria organizacji')
    expect(response.body).to include('Top 10 według pobrań z 30 dni')
    expect(response.body).to include('Top 10 według gwiazdek')
    expect(response.body).to include('Top 10 popularnych w miesiącu')
    expect(response.body).to include('📥 1 tys.')
    expect(response.body).to include('⭐ 12 345')
    expect(response.body).to include('ranking-grid ranking-grid--odd-package-metrics')
    expect(response.body).to include('href="/latest/packages/npm/users/top"')
  end

  def expect_package_registry_and_repository_links(response)
    expect(
      html_element(response.body, "//a[@class='primary-link' " \
                                  "and @href='/repositories/github/alice/app' " \
                                  "and text()='fallback-tool']")
    ).not_to be_nil
    expect(response.body).to include('Nice Ruby app')
    expect(
      html_element(response.body, "//li[.//a[text()='fallback-tool']]//span[contains(@class, 'ranking-list__links')]" \
                                  "/a[@href='https://github.com/alice/app' " \
                                  "and text()='GitHub']")
    ).not_to be_nil
    expect(
      html_element(response.body, "//li[.//a[text()='fallback-tool']]//span[contains(@class, 'ranking-list__links')]" \
                                  '/a[' \
                                  "@href='https://www.npmjs.com/package/fallback-tool' and text()='Pakiet']")
    ).not_to be_nil
  end

  def expect_package_detail_pages(responses)
    expect_npm_package_detail_pages(responses)
    expect_rubygems_package_pages(responses)
    expect_homebrew_package_pages(responses)
    expect_nuget_package_pages(responses)
  end

  def expect_npm_package_detail_pages(responses)
    expect_npm_package_route_statuses(responses)
    expect_npm_package_top_pages(responses)
  end

  def expect_npm_package_route_statuses(responses)
    expect(responses.fetch(:ecosystem).status).to eq(200)
    expect(responses.fetch(:shortcut).status).to eq(200)
    expect(responses.fetch(:period_ecosystem).status).to eq(200)
    expect(responses.fetch(:downloads).status).to eq(404)
    expect(responses.fetch(:dependents).status).to eq(404)
  end

  def expect_npm_package_top_pages(responses)
    expect(responses.fetch(:top).body).to include('Top 100 według pobrań z 30 dni')
    expect(responses.fetch(:user_top).body).to include('Top 100: Repozytoria ludzi, npm, według pobrań z 30 dni')
    expect(responses.fetch(:user_top).body).to include('@scope/tool')
    expect(
      html_element(
        responses.fetch(:user_top).body,
        "//ol[@class='ranking-list' and @aria-labelledby='package-ranking-detail-top']"
      )
    ).not_to be_nil
    expect(responses.fetch(:period_user_top).body).to include('Top 100: Repozytoria ludzi, npm, według pobrań z 30 dni')
  end

  def expect_homebrew_package_pages(responses)
    expect(responses.fetch(:homebrew).body).to include('polish-tool')
    expect(responses.fetch(:homebrew).body).to include('ranking-grid ranking-grid--odd-package-metrics')
    expect(responses.fetch(:homebrew_top).body).to include('Top 100 według instalacji z 30 dni')
    expect(responses.fetch(:homebrew_top).body).to include('Instalacje 30 dni')
  end

  def expect_rubygems_package_pages(responses)
    expect(responses.fetch(:rubygems).body).to include('ranking-grid ranking-grid--compact')
    expect(responses.fetch(:rubygems).body).not_to include('ranking-grid--odd-package-metrics')
    expect(responses.fetch(:rubygems_dependents).body).to include('Top 100 według zależnych pakietów')
    expect(responses.fetch(:rubygems_dependents).body).to include('🔗 23')
  end

  def expect_nuget_package_pages(responses)
    expect(responses.fetch(:nuget).body).to include('Polish.Tool')
    expect(responses.fetch(:nuget_downloads).body).to include('Top 100 według pobrań łącznie')
  end

  def expect_package_index_page(response)
    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Pakiety open source - Polish Open Source</title>')
    expect(response.body).to include('rel="canonical" href="https://rank.example/packages"')
    expect(response.body).not_to include('index-card__repository')
    expect_public_package_index_links(response)
    expect(response.body).to include('"@type": "Dataset"')
  end

  def expect_public_package_index_links(response)
    expect(response.body).to include('href="/latest/packages/npm"')
    expect(response.body).to include('href="/latest/packages/homebrew"')
    expect(response.body).to include('href="/latest/packages/nuget"')
    expect(response.body).to include('href="/latest/packages/maven"')
  end

  def expect_rankings_detail_pages(responses)
    expect_primary_ranking_pages(responses)
    expect_latest_user_ranking_page(responses.fetch(:latest_user))
    expect_latest_city_repository_ranking_page(responses.fetch(:latest_city_repository))
    expect(responses.fetch(:city_organization).status).to eq(200)
    expect(responses.fetch(:city_organization).body).to include('polish-org')
    expect(responses.fetch(:invalid_repository).status).to eq(404)
    expect(responses.fetch(:invalid_city_organization).status).to eq(404)
  end

  def expect_primary_ranking_pages(responses)
    expect(responses.fetch(:user).status).to eq(200)
    expect_ranking_page_hero(
      responses.fetch(:user),
      eyebrow: 'Ranking open source: ludzie',
      title: 'Top 100 według zmergowanych PR'
    )
    expect(responses.fetch(:user).body).to include('Top 100 według zmergowanych PR')
    expect(responses.fetch(:user).body).to include('🚀 8')
    expect(responses.fetch(:repository).status).to eq(200)
    expect_ranking_page_hero(
      responses.fetch(:repository),
      eyebrow: 'Ranking open source: ludzie',
      title: 'Top 100 popularnych repozytoriów'
    )
    expect(responses.fetch(:repository).body).to include('Top 100 popularnych repozytoriów')
    expect(responses.fetch(:organization).status).to eq(200)
    expect_ranking_page_hero(
      responses.fetch(:organization),
      eyebrow: 'Ranking open source: organizacje',
      title: 'Top 100 według gwiazdek'
    )
    expect(responses.fetch(:organization).body).to include('Top 100 według gwiazdek')
    expect(responses.fetch(:organization).body).not_to include('Top 100 organizacji według gwiazdek')
    expect(responses.fetch(:organization_active).status).to eq(200)
    expect_ranking_page_hero(
      responses.fetch(:organization_active),
      eyebrow: 'Ranking open source: organizacje',
      title: 'Top 100 według zmergowanych PR'
    )
    expect(responses.fetch(:organization_active).body).to include('Top 100 według zmergowanych PR')
    expect(responses.fetch(:organization_active).body).not_to include('Top 100 organizacji według zmergowanych PR')
    expect(responses.fetch(:organization_active).body).to include('🚀 3')
    expect(responses.fetch(:organization_repository).status).to eq(200)
    expect_ranking_page_hero(
      responses.fetch(:organization_repository),
      eyebrow: 'Ranking open source: organizacje',
      title: 'Top 100 popularnych repozytoriów organizacji'
    )
    expect(responses.fetch(:organization_repository).body).to include('Top 100 popularnych repozytoriów organizacji')
  end

  def expect_latest_user_ranking_page(response)
    expect(response.status).to eq(200)
    expect_ranking_page_hero(response, eyebrow: 'Ranking open source: ludzie', title: 'Top 100 według gwiazdek')
    expect(response.body).to include('Top 100 według gwiazdek')
    expect(response.body).not_to include('Top 100 użytkowników według gwiazdek')
    expect(response.body).to include('Gwiazdek')
    expect(response.body).not_to include('/icons/medal-gold.svg')
    expect(html_element(response.body, "//ol[@class='ranking-list' and @aria-labelledby='ranking-detail-users']"))
      .not_to be_nil
    podium_classes = html_elements(response.body, "//ol[@aria-labelledby='ranking-detail-users']/li")
                     .first(3)
                     .map { |element| element.attributes['class'] }
    expect(podium_classes).to include('ranking-list__item first_place')
    expect(podium_classes).to include('ranking-list__item second_place')
    expect(podium_classes).to include('ranking-list__item third_place')
    expect(response.body).not_to include('<table>')
  end

  def expect_latest_city_repository_ranking_page(response)
    expect(response.status).to eq(200)
    expect_ranking_page_hero(
      response,
      eyebrow: 'Ranking open source: ludzie',
      title: 'Top 100 repozytoriów według gwiazdek'
    )
    expect(response.body).to include('Top 100 repozytoriów według gwiazdek')
  end

  def expect_ranking_page_hero(response, eyebrow:, title:)
    expect(html_element(response.body, "//section[contains(@class, 'hero')]//p[text()='#{eyebrow}']")).not_to be_nil
    expect(html_element(response.body, "//section[contains(@class, 'hero')]//h1[text()='#{title}']")).not_to be_nil
  end

  def seed_extra_ranked_records(snapshot_repository, period)
    [
      [2, 'bob', 'Bob', 7_000],
      [3, 'carol', 'Carol', 3_000]
    ].each do |id, login, name, stars|
      snapshot_repository.upsert_user(user_attributes(id: id, login: login, name: name, avatar_url: nil))
      snapshot_repository.record_user_stats(user_stats(period, user_id: id, login: login, total_stars: stars))
      snapshot_repository.upsert_repository(repository_attributes(id: id + 10, owner_id: id, owner_login: login))
      snapshot_repository.record_repository_stats(
        repository_stats(period, repository_id: id + 10, owner_id: id, owner_login: login, stars: stars)
      )
    end
  end

  def seed_running_database
    path = empty_database
    database = bootstrapped_database(path)
    run_repository = snapshot_run_repository(database)
    snapshot_repository = snapshot_repository(database)
    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    run_repository.create(period)

    snapshot_repository.upsert_user(user_attributes)
    snapshot_repository.record_user_stats(user_stats(period))
    snapshot_repository.upsert_repository(repository_attributes)
    snapshot_repository.record_repository_stats(repository_stats(period))
    path
  end

  def empty_database
    File.join(Dir.mktmpdir, 'web.sqlite3')
  end

  def bootstrapped_database(path)
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path).tap do |database|
      PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
        database,
        PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
      ).bootstrap!
    end
  end

  def snapshot_run_repository(database)
    PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository.new(database)
  end

  def snapshot_repository(database)
    PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository.new(database)
  end

  def user_attributes(id: 1, login: 'alice', name: 'Alice', avatar_url: 'https://avatars.example/alice.png')
    {
      github_id: id,
      login: login,
      name: name,
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: "#{login}@example.com",
      homepage: "https://#{login}.example",
      html_url: "https://github.com/#{login}",
      avatar_url: avatar_url
    }
  end

  def user_stats(period, user_id: 1, login: 'alice', total_stars: 12_345)
    {
      period_start: period.start_date.to_s,
      user_github_id: user_id,
      login: login,
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: total_stars,
      monthly_stars_delta: 5,
      merged_pull_requests_count: 8
    }
  end

  def repository_attributes(id: 10, owner_id: 1, owner_login: 'alice')
    {
      github_id: id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      name: 'app',
      full_name: "#{owner_login}/app",
      description: 'Nice Ruby app',
      html_url: "https://github.com/#{owner_login}/app",
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false
    }
  end

  def repository_stats(period, repository_id: 10, owner_id: 1, owner_login: 'alice', stars: 12_345)
    {
      period_start: period.start_date.to_s,
      repository_github_id: repository_id,
      owner_github_id: owner_id,
      owner_login: owner_login,
      owner_city: 'Kraków',
      owner_country: 'Poland',
      stargazers_count: stars,
      monthly_stars_delta: 5
    }
  end

  def organization_snapshot(period)
    PolishOpenSourceRank::Contexts::Ranking::Domain::OrganizationSnapshot.new(
      period: period,
      platform: 'github',
      source_id: 30,
      login: 'polish-org',
      name: 'Polish Org',
      location_raw: 'Warsaw, Poland',
      city: 'Warszawa',
      country: 'Poland',
      email: 'org@example.com',
      homepage: 'https://polish-org.example',
      html_url: 'https://github.com/polish-org',
      avatar_url: 'https://avatars.example/polish-org.png',
      public_repository_count: 1,
      total_stars: 8_765,
      monthly_stars_delta: 12,
      merged_pull_requests_count: 3,
      members_count: 42
    )
  end

  def organization_repository_snapshot(period)
    PolishOpenSourceRank::Contexts::Ranking::Domain::OrganizationRepositorySnapshot.new(
      period: period,
      platform: 'github',
      source_id: 300,
      organization_source_id: 30,
      organization_login: 'polish-org',
      organization_city: 'Warszawa',
      organization_country: 'Poland',
      name: 'toolkit',
      full_name: 'polish-org/toolkit',
      description: 'Shared tooling',
      html_url: 'https://github.com/polish-org/toolkit',
      homepage: nil,
      language: 'Ruby',
      fork: false,
      archived: false,
      stars: 8_765,
      monthly_stars_delta: 12
    )
  end

  def seed_package_records(database, period)
    seed_package(database, period, '@scope/tool', downloads_30d: 1_000)
    seed_package(database, period, 'fallback-tool', downloads_30d: 900, repository_url: nil)
    seed_package(database, period, 'rack', ecosystem: 'rubygems', downloads_total: 50_000, dependents_count: 23)
    seed_package(database, period, 'polish-tool', ecosystem: 'homebrew', downloads_30d: 250)
    seed_package(database, period, 'Polish.Tool', ecosystem: 'nuget', downloads_total: 12_000)
    seed_package(database, period, 'pl.example:polish-tool', ecosystem: 'maven')
    link_package_repository(database, period, '@scope/tool')
    link_package_repository(database, period, 'fallback-tool')
  end

  def seed_package(database, period, name, attributes = {})
    attributes = { ecosystem: 'npm' }.merge(attributes)
    ecosystem = attributes.fetch(:ecosystem)
    normalized_name = name.downcase
    repository_url = attributes.fetch(:repository_url) { "https://github.com/#{name.delete_prefix('@')}" }
    database.execute(
      <<~SQL,
        INSERT INTO registry_packages(
          ecosystem, package_name, normalized_package_name, registry_url, repository_url, homepage_url,
          license, latest_version, status, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, 'MIT', '1.0.0', 'active', '2026-05-23T12:00:00Z')
        ON CONFLICT(ecosystem, normalized_package_name) DO UPDATE SET updated_at = excluded.updated_at
      SQL
      [
        ecosystem,
        name,
        normalized_name,
        package_registry_url(ecosystem, name),
        repository_url,
        "https://example.com/#{normalized_name}"
      ]
    )
    seed_package_snapshot(database, period, attributes.merge(normalized_name: normalized_name))
  end

  def seed_package_snapshot(database, period, attributes)
    database.execute(
      <<~SQL,
        INSERT INTO registry_package_snapshots(
          ecosystem, normalized_package_name, period_start, downloads_total, downloads_30d, downloads_7d,
          dependents_count, dependent_repositories_count, latest_version, latest_release_at, observed_at
        )
        VALUES (?, ?, ?, ?, ?, NULL, ?, 1, '1.0.0', '2026-05-01T00:00:00Z', '2026-05-23T12:00:00Z')
      SQL
      [
        attributes.fetch(:ecosystem),
        attributes.fetch(:normalized_name),
        period.start_date.to_s,
        attributes[:downloads_total],
        attributes[:downloads_30d],
        attributes[:dependents_count]
      ]
    )
  end

  def package_registry_url(ecosystem, name)
    return "https://formulae.brew.sh/formula/#{name}" if ecosystem == 'homebrew'
    return "https://www.nuget.org/packages/#{name}" if ecosystem == 'nuget'
    return "https://central.sonatype.com/artifact/#{name.tr(':', '/')}" if ecosystem == 'maven'

    "https://www.npmjs.com/package/#{name}"
  end

  def link_package_repository(database, period, package_name)
    scan_id = period.start_date.month * 1_000
    manifest_id = seed_package_scan(database, period, scan_id, package_name)
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO registry_package_links(
          manifest_id, ecosystem, normalized_package_name, match_confidence, matched, checked_at
        )
        VALUES (?, 'npm', ?, 'high', 1, '2026-05-23T12:00:00Z')
      SQL
      [manifest_id, package_name.downcase]
    )
  end

  def seed_package_scan(database, period, scan_id, package_name)
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO package_repository_scans(
          id, period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
        )
        VALUES (?, ?, 'user', 'github', 10, 'alice/app', 'scanned', '2026-05-23T12:00:00Z')
      SQL
      [scan_id, period.start_date.to_s]
    )
    database.dataset(:package_manifests).insert(
      repository_scan_id: scan_id,
      ecosystem: 'npm',
      path: package_name == '@scope/tool' ? 'package.json' : "packages/#{package_name}/package.json",
      package_name: package_name,
      normalized_package_name: package_name.downcase,
      confidence: 'high',
      parse_status: 'parsed',
      parser_version: 'test',
      parsed_at: '2026-05-23T12:00:00Z'
    )
  end

  def cookie_header(*responses)
    responses.flat_map { |response| Array(response['Set-Cookie']) }
             .map { |cookie| cookie.split(';').first }
             .join('; ')
  end

  def internal_auth_env(username: 'internal', password: 'local-internal-basic-auth-password')
    credentials = ["#{username}:#{password}"].pack('m0')
    { 'HTTP_AUTHORIZATION' => "Basic #{credentials}" }
  end

  def csrf_token_from(response)
    response.body.match(/name="csrf_token" value="([^"]+)"/).captures.first
  end

  def expect_locale_cookie(response, value)
    expect(response['Set-Cookie']).to include(value)
    expect(response['Set-Cookie']).to include('httponly')
    expect(response['Set-Cookie']).to include('samesite=lax')
  end

  def sign_in_with_github(request)
    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
  end

  def finish_discord_auth(request, github_callback)
    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )
  end

  def without_discord_channel_env!
    ENV.delete('DISCORD_INVITE_CHANNEL_ID')
    ENV.delete('DISCORD_WELCOME_CHANNEL_ID')
  end

  def reset_app_memoized_dependencies
    %i[
      @configuration
      @composition
      @public_page_state
    ].each do |ivar|
      described_class.remove_instance_variable(ivar) if described_class.instance_variable_defined?(ivar)
    end
  end

  def expect_poland_ranking_page(response)
    polish_home_description = 'Ranking polskich programistów, organizacji i projektów open source. ' \
                              'Jesteś w rankingu? Pobierz badge i dołącz do Discord.'

    expect(response.status).to eq(200)
    expect_body_to_include(
      response,
      '<title>Open Source Polska</title>',
      "name=\"description\" content=\"#{polish_home_description}\"",
      'rel="canonical" href="https://rank.example/"',
      'rel="alternate" hreflang="en" href="https://rank.example/en"',
      'property="og:title" content="Open Source Polska"',
      "property=\"og:description\" content=\"#{polish_home_description}\"",
      'property="og:image" content="https://rank.example/images/polish_open_source_banner.webp"',
      '<p class="eyebrow">Ranking open source: ludzie</p>',
      '<h1>Polska</h1>',
      '"@type": "WebSite"',
      '"@type": "CollectionPage"',
      '"name": "Top 10 według gwiazdek"',
      '⭐ 12 345',
      '🚀 8',
      'alice/app',
      'class="location-notice js-first-visit-notice"',
      'data-storage-key="polishOpenSourceRank.locationNoticeSeen"',
      'hidden',
      'Nie ma cię w rankingu?',
      'href="https://github.com/settings/profile#user_profile_location"',
      '<strong>Zmień lokalizację</strong>',
      'Maciej Ciemborowicz',
      'href="https://maciej-ciemborowicz.eu/"',
      'href="https://github.com/ciembor"',
      'href="https://www.linkedin.com/in/maciej-ciemborowicz/"',
      'href="https://x.com/ciembor"',
      '>homepage</span>',
      '>github</span>',
      '>x</span>',
      '>linkedin</span>',
      'href="/latest/users/top"',
      'href="/latest/organizations"',
      'href="/languages"',
      'href="https://github.com/ciembor/polish-open-source"',
      'Repozytorium',
      'Zobacz top 100',
      'href="/editions"',
      'application/ld+json'
    )
    expect_active_nav_link(response.body, '/latest')
    expect(response.body).not_to include('href="/latest/organizations/top"')
    expect(response.body).not_to include('href="/latest/organization-repositories/top"')
  end

  def expect_historical_month_page(response)
    expect_body_to_include(
      response,
      'Ludzie',
      'Repozytoria ludzi',
      'Organizacje',
      'Repozytoria organizacji',
      'polish-org/toolkit',
      'href="/2026-04/organizations/top"',
      'href="/2026-04/organization-repositories/top"'
    )
  end

  def expect_english_locale_page(response)
    english_home_description = 'Ranking of Polish programmers, organizations, and open-source projects. ' \
                               'Are you in the ranking? Get your badge and join Discord.'

    expect_body_to_include(
      response,
      '<html lang="en">',
      '>Poland</a>',
      '>More cities</summary>',
      'Top 10 by stars',
      'Repositories',
      'rel="canonical" href="https://rank.example/en"',
      'rel="alternate" hreflang="pl" href="https://rank.example/"',
      'rel="alternate" hreflang="x-default" href="https://rank.example/"',
      '<title>Polish Open Source</title>',
      "name=\"description\" content=\"#{english_home_description}\"",
      'property="og:title" content="Polish Open Source"',
      '<meta name="robots" content="index,follow,max-image-preview:large">',
      'href="/latest?lang=pl"'
    )
  end

  def expect_organization_ranking_page(response)
    expect(response.status).to eq(200)
    expect_body_to_include(
      response,
      '<title>Organizacje open source - Polska</title>',
      'rel="canonical" href="https://rank.example/latest/organizations"',
      'rel="alternate" hreflang="en" href="https://rank.example/en/latest/organizations"',
      'property="og:title" content="Organizacje open source - Polska"',
      '<p class="eyebrow">Ranking open source: organizacje</p>',
      '<h1>Polska</h1>',
      'Organizacje i ich repozytoria uporządkowane według gwiazdek, miesięcznej popularności oraz zmergowanych PR.',
      'Top 10 według zmergowanych PR w miesiącu',
      '🚀 3',
      'polish-org/toolkit',
      'href="/latest/organizations/locations/krakow"',
      'href="/languages"',
      'href="/latest/organizations/top"',
      'href="/latest/organizations/active"',
      'href="/latest/organization-repositories/top"',
      'href="/latest/organization-repositories/trending"',
      'Więcej miast'
    )
    expect_active_nav_link(response.body, '/latest/organizations')
    expect(response.body).not_to include('href="/latest/users/top"')
    expect(response.body).not_to include('href="/latest/repositories/top"')
  end

  def expect_user_profile_page(ranking_response:, profile_response:, badge_response:, missing_response:)
    expect(ranking_response.body).to include('href="/users/github/alice"')
    expect(profile_response.status).to eq(200)
    expect_body_to_include(
      profile_response,
      '<title>alice - Open Source Polska</title>',
      'rel="canonical" href="https://rank.example/users/github/alice"',
      'src="https://avatars.example/alice.png"',
      '"@type": "ProfilePage"',
      'Profil w rankingu',
      'Pozycja w rankingu Polski',
      'Pozycja w Kraków',
      'Najmocniejsze repozytorium',
      'class="profile-action"',
      '#1',
      'Najlepsze projekty',
      'alice/app',
      '/icons/medal-gold.svg',
      '12 345'
    )
    expect(profile_response.body).not_to include('class="ranking-action"')
    expect(profile_response.body).not_to include('/badges/users/github/alice.svg')
    expect(badge_response.status).to eq(200)
    expect(badge_response.content_type).to include('image/svg+xml')
    expect_body_to_include(badge_response, 'Polish Open Source', '1st', 'href="https://rank.example/latest"')
    expect(missing_response.status).to eq(404)
  end

  def expect_signed_in_profile(github_callback, profile)
    expect(github_callback.status).to eq(302)
    expect(github_callback.location).to eq('http://example.org/users/github/alice')
    expect_body_to_include(
      profile,
      'Twój dostęp Discord',
      'Dołącz do Elite Discorda',
      'href="/auth/discord"',
      'Dostępne grupy',
      'Odznaka',
      'Odznaki repozytoriów',
      '<p class="badge-preview__label">alice/app</p>',
      'class="badge-markdown"',
      'class="badge-markdown__copy js-copy-badge-markdown"',
      'data-copy-label="Kopiuj"',
      'data-copy-done-label="Skopiowano"',
      'Top 100 PL',
      'Top 100 Kraków',
      '/badges/users/github/alice.svg',
      '/badges/repositories/github/alice/app.svg'
    )
    expect(profile.body).not_to include('Odznaka na GitHub')
    expect(profile.body).not_to include('Ranking Polski')
    expect(profile.body).not_to include('Ranking Kraków')
    expect(profile.body).not_to include('Nie ma cię w rankingu?')
    expect(profile.body).not_to include('polishOpenSourceRank.locationNoticeSeen')
    expect_active_nav_link(profile.body, '/users/github/alice')
    expect(profile.body.index('id="profile-discord-heading"')).to be < profile.body.index('id="profile-badge-heading"')
    expect(profile.body.index('id="profile-badge-heading"')).to be < profile.body.index('id="profile-summary-heading"')
    expect(profile.body).not_to include('Discord niepołączony')
  end

  def expect_queued_discord_sync(request, discord_callback)
    expect(discord_callback.status).to eq(302)
    expect(discord_callback.location).to eq('https://discord.com/channels/guild-1/invite-channel')
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(discord_callback))
    expect(profile.body).to include('Alice Discord')
    expect(profile.body).to include('Synchronizacja Discord jest w kolejce')
  end

  def expect_repository_profile_page(**responses)
    ranking_response = responses.fetch(:ranking_response)
    profile_response = responses.fetch(:profile_response)
    owner_profile_response = responses.fetch(:owner_profile_response)
    badge_response = responses.fetch(:badge_response)
    expect(ranking_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.status).to eq(200)
    expect(profile_response.body).to include('<title>alice/app - projekt GitHub</title>')
    expect(profile_response.body).to include('rel="canonical" href="https://rank.example/repositories/github/alice/app"')
    expect(profile_response.body).to include('"@type": "SoftwareSourceCode"')
    expect(profile_response.body).to include('class="profile-action"')
    expect(profile_response.body).not_to include('class="ranking-action"')
    expect(profile_response.body).to include('/icons/medal-gold.svg')
    expect(profile_response.body).to include('<h2 id="repository-star-history-heading">Historia gwiazdek</h2>')
    expect(profile_response.body).to include('href="https://www.star-history.com/alice/app"')
    expect(profile_response.body).to include(
      'src="https://api.star-history.com/chart?repos=alice%2Fapp&amp;type=date&amp;legend=top-left"'
    )
    expect(profile_response.body).not_to include('Odznaka na GitHub')
    expect(profile_response.body).not_to include('/badges/repositories/github/alice/app.svg')
    expect(owner_profile_response.body).to include('<h2 id="repository-badge-heading">Odznaka</h2>')
    expect(owner_profile_response.body).not_to include('Odznaka na GitHub')
    expect(owner_profile_response.body).to include('class="badge-markdown__copy js-copy-badge-markdown"')
    expect(owner_profile_response.body).to include('/badges/repositories/github/alice/app.svg')
    expect(owner_profile_response.body).to include(
      '[![Badge Polish Repo](https://rank.example/badges/repositories/github/alice/app.svg)]'
    )
    expect(badge_response.status).to eq(200)
    expect(badge_response.content_type).to include('image/svg+xml')
    expect_body_to_include(badge_response, 'Polish .rb Repo', '1st', '#dc143c', 'href="https://rank.example/latest"')
    expect(responses.fetch(:short_badge_response).status).to eq(200)
    expect(responses.fetch(:missing_response).status).to eq(404)
  end

  def expect_editions_page(response)
    expect(response.status).to eq(200)
    expect_body_to_include(
      response,
      '<title>Edycje rankingu open source</title>',
      '>Edycje</h1>',
      '"@type": "CollectionPage"',
      'property="og:image" content="https://rank.example/images/polish_open_source_front.webp"',
      'kwiecień 2026',
      'Top projekty',
      'Top użytkownicy: gwiazdki',
      'Top organizacje: gwiazdki',
      'polish-org',
      'href="/2026-04"',
      'href="/editions/2025"'
    )
    expect(
      html_element(response.body, "//a[@class='hero__image-link' and @href='/auth/github']" \
                                  "/img[@class='hero__image' and @src='/images/polish_open_source_front.webp']")
    ).not_to be_nil
    expect(
      html_element(response.body, "//ol[@class='edition-toplist']" \
                                  "//a[contains(@class, 'edition-toplist__primary-link')]" \
                                  "/span[@class='edition-toplist__primary-text']")
    ).not_to be_nil
    expect_active_nav_link(response.body, '/editions')
  end

  def expect_about_page(response)
    expect(response.status).to eq(200)
    expect_body_to_include(
      response,
      '<title>O Polish Open Source</title>',
      '"@type": "AboutPage"',
      '"@type": "WebSite"',
      'property="og:image" content="https://rank.example/images/polish_open_source_front.webp"',
      'Misja',
      'Rankingi',
      'Pakiety',
      'Źródła danych',
      'Wróć na górę',
      'href="#mission"',
      'href="#rankings"',
      'GitHub',
      'GitLab',
      'Codeberg',
      'Maciej Ciemborowicz',
      'src="/images/maciej-ciemborowicz.jpg"',
      'href="/latest"'
    )
    expect(
      html_element(response.body, "//section[@id='mission']//div[contains(@class, 'about-section__eyebrow-row')]" \
                                  "/p[contains(@class, 'eyebrow')]/following-sibling::a" \
                                  "[contains(@class, 'about-section__back-link') and @href='#about-top']")
    ).not_to be_nil
    expect(
      html_element(response.body, "//section[@id='mission']//h2/following-sibling::a" \
                                  "[contains(@class, 'about-section__back-link')]")
    ).to be_nil
    expect_active_nav_link(response.body, '/about')
    expect(response.body).not_to include('Programista i autor projektu')
    expect(response.body).not_to include('//locations')
  end

  def expect_active_nav_link(body, href)
    xpath = "//nav[contains(@class, 'nav')]//a[@href='#{href}' and contains(@class, 'is-active')]"

    expect(html_element(body, xpath)).not_to be_nil
  end

  def expect_body_to_include(response, *fragments)
    fragments.each { |fragment| expect(response.body).to include(fragment) }
  end

  def stub_discord_invite_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.body = body
    response.instance_variable_set(:@read, true)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end
end

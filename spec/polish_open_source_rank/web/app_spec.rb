# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::App do
  around do |example|
    old_env = ENV.to_h
    old_github_oauth_client = described_class.github_oauth_client
    old_discord_oauth_client = described_class.discord_oauth_client
    old_discord_gateway = described_class.discord_gateway
    ENV['BASE_URL'] = 'https://rank.example'
    ENV.delete('APP_BASE_PATH')
    example.run
  ensure
    ENV.replace(old_env)
    described_class.set :github_oauth_client, old_github_oauth_client
    described_class.set :discord_oauth_client, old_discord_oauth_client
    described_class.set :discord_gateway, old_discord_gateway
    reset_app_memoized_dependencies
  end

  # rubocop:disable RSpec/MultipleExpectations
  it 'renders the Poland ranking with SEO metadata' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Polska open-source ranking</title>')
    expect(response.body).to include('rel="canonical" href="https://rank.example/latest"')
    expect(response.body).to include('rel="alternate" hreflang="en" href="https://rank.example/en/latest"')
    expect(response.body).to include('property="og:title" content="Polska open-source ranking"')
    expect(response.body).to include('property="og:image" content="https://rank.example/images/polish_open_source_banner.webp"')
    expect(response.body).to include('"@type": "WebSite"')
    expect(response.body).to include('"@type": "CollectionPage"')
    expect(response.body).to include('"name": "Top 10 według gwiazdek"')
    expect(response.body).to include('alice/app')
    expect(response.body).to include('href="/latest/users/top"')
    expect(response.body).to include('Zobacz top 100')
    expect(response.body).to include('href="/editions"')
    expect(response.body).to include('application/ld+json')
  end
  # rubocop:enable RSpec/MultipleExpectations

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
    response = Rack::MockRequest.new(described_class).get('/2026-04/locations/krakow')
    month_response = Rack::MockRequest.new(described_class).get('/2026-04')

    expect(latest_response.status).to eq(200)
    expect(latest_city_response.status).to eq(200)
    expect(response.status).to eq(200)
    expect(month_response.status).to eq(200)
    expect(response.body).to include('alice/app')
    expect(response.body).to include('rel="canonical" href="https://rank.example/2026-04/locations/krakow"')
  end

  it 'renders latest and explicit month slugs while the snapshot is still running with stored stats' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    latest_response = Rack::MockRequest.new(described_class).get('/latest')
    month_response = Rack::MockRequest.new(described_class).get('/2026-04')

    expect(latest_response.body).to include('alice/app')
    expect(month_response.status).to eq(200)
    expect(month_response.body).to include('alice/app')
  end

  it 'renders full top 100 pages for each ranking type', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    user_response = Rack::MockRequest.new(described_class).get('/2026-04/locations/krakow/users/active')
    repo_response = Rack::MockRequest.new(described_class).get('/2026-04/repositories/trending')
    latest_user_response = Rack::MockRequest.new(described_class).get('/latest/users/top')
    latest_city_response = Rack::MockRequest.new(described_class).get('/latest/locations/krakow/repositories/top')
    invalid_response = Rack::MockRequest.new(described_class).get('/2026-04/repositories/active')

    expect(user_response.status).to eq(200)
    expect(user_response.body).to include('Top 100 aktywnych użytkowników')
    expect(repo_response.status).to eq(200)
    expect(repo_response.body).to include('Top 100 trendujących repozytoriów')
    expect(latest_user_response.status).to eq(200)
    expect(latest_user_response.body).to include('Gwiazdek')
    expect(latest_user_response.body).not_to include('/icons/medal-gold.svg')
    expect(latest_user_response.body).to include('<ol class="ranking-list" aria-labelledby="ranking-detail-users">')
    expect(latest_user_response.body).to include('<li class="ranking-list__item first_place">')
    expect(latest_user_response.body).to include('<li class="ranking-list__item second_place">')
    expect(latest_user_response.body).to include('<li class="ranking-list__item third_place">')
    expect(latest_user_response.body).not_to include('<table>')
    expect(latest_city_response.status).to eq(200)
    expect(latest_city_response.body).to include('Top 100 repozytoriów według gwiazdek')
    expect(invalid_response.status).to eq(404)
  end

  # rubocop:disable RSpec/ExampleLength
  it 'renders user profile pages from ranking users', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    ranking_response = request.get('/latest/users/top')
    profile_response = request.get('/users/github/alice')
    badge_response = request.get('/badges/users/github/alice.svg')
    missing_response = request.get('/users/github/missing')

    expect(ranking_response.body).to include('href="/users/github/alice"')
    expect(profile_response.status).to eq(200)
    expect(profile_response.body).to include('<title>Alice - profil GitHub</title>')
    expect(profile_response.body).to include('rel="canonical" href="https://rank.example/users/github/alice"')
    expect(profile_response.body).to include('src="https://avatars.example/alice.png"')
    expect(profile_response.body).to include('Profil na GitHub')
    expect(profile_response.body).to include('"@type": "ProfilePage"')
    expect(profile_response.body).to include('"@type": "Person"')
    expect(profile_response.body).to include('"@type": "BreadcrumbList"')
    expect(profile_response.body).to include('Profil w rankingu')
    expect(profile_response.body).to include('Pozycja w rankingu Polski')
    expect(profile_response.body).to include('Pozycja w Kraków')
    expect(profile_response.body).to include('Najmocniejsze repozytorium')
    expect(profile_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.body).to include('#1')
    expect(profile_response.body).to include('Najlepsze projekty')
    expect(profile_response.body).not_to include('/badges/users/github/alice.svg')
    expect(profile_response.body).not_to include(
      '[![Polish Open Source badge](https://rank.example/badges/users/github/alice.svg)]'
    )
    expect(profile_response.body).to include('alice/app')
    expect(profile_response.body).to include('/icons/medal-gold.svg')
    expect(profile_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.body).to include('12 345')
    expect(badge_response.status).to eq(200)
    expect(badge_response.content_type).to include('image/svg+xml')
    expect(badge_response.body).to include('Polish Open Source')
    expect(badge_response.body).to include('1st')
    expect(badge_response.body).to include('href="https://rank.example/latest"')
    expect(missing_response.status).to eq(404)
  end
  # rubocop:enable RSpec/ExampleLength

  # rubocop:disable RSpec/ExampleLength
  it 'logs public GitHub users in and syncs their Discord account', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['DISCORD_INVITE_CHANNEL_ID'] = 'invite-channel'
    ENV['DISCORD_GUILD_ID'] = 'guild-1'
    ENV['DISCORD_ROLE_TOP_10_PL'] = 'role-top-10'
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

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
    profile = request.get('/users/github/alice', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(github_callback.status).to eq(302)
    expect(github_callback.location).to eq('http://example.org/users/github/alice')
    expect(profile.body).to include('Twój dostęp Discord')
    expect(profile.body).to include('Dołącz do Elite Discorda')
    expect(profile.body).to include('href="/auth/discord"')
    expect(profile.body).to include('Kanały do pisania')
    expect(profile.body).to include('Top 10 PL')
    expect(profile.body).to include('Top 100 PL')
    expect(profile.body).to include('Top 100 Kraków')
    expect(profile.body).to include('/badges/users/github/alice.svg')
    expect(profile.body).to include('/badges/repositories/github/alice/app.svg')
    expect(profile.body).to include('Polish Open Source')
    expect(profile.body.index('id="profile-discord-heading"')).to be < profile.body.index('id="profile-badge-heading"')
    # "Profile" also appears in the navbar label for logged-in users. Assert using stable section markers
    # instead of the translated heading text.
    expect(profile.body.index('id="profile-badge-heading"')).to be < profile.body.index('id="profile-summary-heading"')
    expect(profile.body).not_to include('Discord niepołączony')

    discord_start = request.get('/auth/discord', 'HTTP_COOKIE' => cookie_header(github_callback))
    discord_state = Rack::Utils.parse_query(URI(discord_start.location).query).fetch('state')
    discord_callback = request.get(
      "/auth/discord/callback?code=discord-code&state=#{discord_state}",
      'HTTP_COOKIE' => cookie_header(discord_start)
    )

    expect(discord_callback.status).to eq(302)
    expect(discord_callback.location).to eq('https://discord.com/channels/guild-1/invite-channel')
    expect(discord_gateway.synced).to include(
      discord_user_id: 'discord-1',
      access_token: 'discord-access',
      github_login: 'alice'
    )
    expect(discord_gateway.welcome).to include(channel_id: 'invite-channel', discord_user_id: 'discord-1')
    expect(discord_gateway.welcome.fetch(:profile)).to include(
      login: 'alice',
      html_url: 'https://github.com/alice'
    )
    expect(discord_gateway.welcome.fetch(:profile).fetch(:repositories).first).to include(
      full_name: 'alice/app',
      html_url: 'https://github.com/alice/app',
      stargazers_count: 12_345
    )
    expect(discord_gateway.welcome.fetch(:access)).to include(country_rank: 1, city_rank: 1)
    expect(discord_gateway.welcome.fetch(:role_ids)).to include('role-top-10', 'role-top-100', 'role-krakow')
    expect(discord_gateway.synced.fetch(:desired_role_ids)).to include('role-top-10', 'role-top-100', 'role-krakow')
    expect(github_client.exchanged).to eq(['github-code'])
    expect(discord_client.exchanged).to eq(['discord-code'])
  end
  # rubocop:enable RSpec/ExampleLength

  it 'creates a public profile for GitHub users with a supported location' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    github_client = FakeGitHubOAuthClient.new('outsider', id: 40, location: 'Poznan, Poland')
    described_class.set :github_oauth_client, github_client
    request = Rack::MockRequest.new(described_class)

    github_start = request.get('/auth/github')
    github_state = Rack::Utils.parse_query(URI(github_start.location).query).fetch('state')
    github_callback = request.get(
      "/auth/github/callback?code=github-code&state=#{github_state}",
      'HTTP_COOKIE' => cookie_header(github_start)
    )
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

  it 'returns to the profile with a retry message when Discord member sync fails' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
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
    profile = request.get(discord_callback.location, 'HTTP_COOKIE' => cookie_header(discord_callback))

    expect(discord_callback.status).to eq(302)
    expect(discord_callback.location).to eq('http://example.org/users/github/alice')
    expect(profile.body).to include('Nie udało się zsynchronizować konta Discord')
  end

  it 'rejects Discord sync when the logged-in GitHub profile is no longer ranked' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
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
    logout = request.post('/logout', 'HTTP_COOKIE' => cookie_header(github_callback))

    expect(profile.body).to include('Dołącz do Elite Discorda')
    expect(profile.body).to include('Kanały do pisania')
    expect(profile.body).to include('/auth/discord')
    expect(logout.status).to eq(303)
    expect(logout.location).to eq('http://example.org/latest')
  end

  it 'keeps podium medals on profile pages', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    expect(request.get('/users/github/alice').body).to include('/icons/medal-gold.svg')
    expect(request.get('/users/github/bob').body).to include('/icons/medal-silver.svg')
    expect(request.get('/users/github/carol').body).to include('/icons/medal-bronze.svg')
  end

  # rubocop:disable RSpec/ExampleLength
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

    expect(ranking_response.body).to include('href="/repositories/github/alice/app"')
    expect(profile_response.status).to eq(200)
    expect(profile_response.body).to include('<title>alice/app - projekt GitHub</title>')
    expect(profile_response.body).to include('rel="canonical" href="https://rank.example/repositories/github/alice/app"')
    expect(profile_response.body).to include('"@type": "SoftwareSourceCode"')
    expect(profile_response.body).to include('/icons/medal-gold.svg')
    expect(profile_response.body).not_to include('Odznaka na GitHub')
    expect(profile_response.body).not_to include('/badges/repositories/github/alice/app.svg')
    expect(owner_profile_response.body).to include('Odznaka na GitHub')
    expect(owner_profile_response.body).to include('/badges/repositories/github/alice/app.svg')
    expect(owner_profile_response.body).to include(
      '[![Badge Polish Repo](https://rank.example/badges/repositories/github/alice/app.svg)]'
    )
    expect(badge_response.status).to eq(200)
    expect(badge_response.content_type).to include('image/svg+xml')
    expect(badge_response.body).to include('Polish Repo')
    expect(badge_response.body).to include('1st')
    expect(badge_response.body).to include('#dc143c')
    expect(badge_response.body).to include('href="https://rank.example/latest"')
    expect(short_badge_response.status).to eq(200)
    expect(missing_response.status).to eq(404)
  end
  # rubocop:enable RSpec/ExampleLength

  # rubocop:disable RSpec/MultipleExpectations
  it 'renders editions with year pagination' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"

    response = Rack::MockRequest.new(described_class).get('/editions')

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>Edycje rankingu open source</title>')
    expect(response.body).to include('>Edycje</h1>')
    expect(response.body).to include('"@type": "CollectionPage"')
    expect(response.body).to include('property="og:image" content="https://rank.example/images/polish_open_source_join.webp"')
    expect(response.body).to include('kwiecień 2026')
    expect(response.body).to include('Top projekty')
    expect(response.body).to include('Top użytkownicy: gwiazdki')
    expect(response.body).to include('Top użytkownicy: aktywność')
    expect(response.body).to include('href="/2026-04"')
    expect(response.body).to include('href="/editions/2025"')
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

    expect(response.status).to eq(200)
    expect(response.body).to include('<title>O Polish Open Source Rank</title>')
    expect(response.body).to include('"@type": "AboutPage"')
    expect(response.body).to include('"@type": "WebSite"')
    expect(response.body).to include('property="og:image" content="https://rank.example/images/pos_cut.png"')
    expect(response.body).to include('Misja')
    expect(response.body).to include('Zakres danych')
    expect(response.body).to include('GitHub')
    expect(response.body).to include('GitLab')
    expect(response.body).to include('Codeberg')
    expect(response.body).to include('Maciej Ciemborowicz')
    expect(response.body).to include('href="/latest/locations/krakow"')
    expect(response.body).not_to include('//locations')
  end

  it 'keeps core public pages semantically structured', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    rankings = request.get('/latest')
    about = request.get('/about')
    profile = request.get('/users/github/alice')

    expect(rankings.body.scan('<h1').length).to eq(1)
    expect(about.body.scan('<h1').length).to eq(1)
    expect(profile.body.scan('<h1').length).to eq(1)
    expect(rankings.body).to include('<main id="main-content">')
    expect(rankings.body).to include('role="navigation" aria-label="Język"')
    expect(rankings.body).to include('src="/icons/polish-open-source.png" alt="" aria-hidden="true"')
    expect(rankings.body).to include('src="/images/polish_open_source_join_wide.webp" alt="" aria-hidden="true"')
    expect(rankings.body).to include('<article class="ranking-table" aria-labelledby="ranking-users-top">')
  end
  # rubocop:enable RSpec/MultipleExpectations

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
    expect(polish_response.body).to include('Użytkownicy')
    expect(polish_response.body).to include('Zobacz top 100')
    expect(polish_response.body).to include('href="/en"')
  end

  it 'renders English content by explicit locale and cookie' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    request = Rack::MockRequest.new(described_class)

    english_response = request.get('/en/latest')
    cookie_response = request.get('/latest', 'HTTP_COOKIE' => 'locale=en')

    expect(english_response.body).to include('<html lang="en">')
    expect(english_response.body).to include('>Poland</a>')
    expect(english_response.body).to include('>More cities</summary>')
    expect(english_response.body).to include('Top 10 by stars')
    expect(english_response.body).to include('Repositories')
    expect(english_response.body).to include('rel="canonical" href="https://rank.example/en/latest"')
    expect(english_response.body).to include('href="/latest?lang=pl"')
    expect(Array(english_response['Set-Cookie']).join("\n")).to include('locale=en')
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
    expect(english_redirect['Set-Cookie']).to include('locale=en')

    expect(polish_redirect.status).to eq(302)
    expect(polish_redirect.location).to eq('http://example.org/latest')
    expect(polish_redirect['Set-Cookie']).to include('locale=pl')

    expect(prefixed_polish_redirect.status).to eq(302)
    expect(prefixed_polish_redirect.location).to eq('http://example.org/latest')
    expect(prefixed_polish_redirect['Set-Cookie']).to include('locale=pl')
  end

  it 'renders links and assets under a configured app base path' do
    ENV['DATABASE_URL'] = "sqlite://#{seed_database}"
    ENV['BASE_URL'] = 'https://rank.example'
    ENV['APP_BASE_PATH'] = '/'

    response = Rack::MockRequest.new(described_class).get('/')

    expect(response.body).to include('rel="canonical" href="https://rank.example/latest"')
    expect(response.body).to match(%r{href="/css/application\.css\?v=\d+"})
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
    not_modified = request.get('/latest', 'HTTP_IF_NONE_MATCH' => response['ETag'])
    badge_response = request.get('/badges/users/github/alice.svg')

    expect(response['Cache-Control']).to eq('public, max-age=0, must-revalidate')
    expect(response['ETag']).to match(/\A".+"\z/)
    expect(response['Vary']).to include('Accept-Language')
    expect(response['Vary']).to include('Cookie')
    expect(not_modified.status).to eq(304)
    expect(badge_response['Cache-Control']).to eq('public, max-age=300, stale-while-revalidate=3600')
    expect(badge_response['ETag']).to match(/\A".+"\z/)
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
    internal = request.get('/internal/jobs')

    expect(github_start['Cache-Control']).to eq('no-store')
    expect(profile['Cache-Control']).to eq('private, no-cache')
    expect(internal['Cache-Control']).to eq('no-store')
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
    expect(robots.body).to include('Sitemap: https://rank.example/sitemap.xml')
    expect(sitemap.status).to eq(200)
    expect(sitemap.content_type).to include('application/xml')
    expect(sitemap.body).to include('<loc>https://rank.example/latest</loc>')
    expect(sitemap.body).to include('<loc>https://rank.example/en/latest</loc>')
    expect(sitemap.body).to include('<loc>https://rank.example/about</loc>')
    expect(sitemap.body).to include('<loc>https://rank.example/en/users/github/alice</loc>')
    expect(sitemap.body).to include('<lastmod>')
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
    expect(about.body).to include('property="og:title" content="O Polish Open Source Rank"')
    expect(about.body).to include('name="twitter:card" content="summary_large_image"')

    expect(editions.body).to include('rel="canonical" href="https://rank.example/editions"')
    expect(editions.body).to include('property="og:image" content="https://rank.example/images/polish_open_source_join.webp"')

    expect(user_profile.body).to include('rel="canonical" href="https://rank.example/users/github/alice"')
    expect(user_profile.body).to include('property="og:type" content="profile"')
    expect(user_profile.body).to include('name="twitter:image" content="https://rank.example/images/pos.png"')

    expect(repository_profile.body).to include('rel="canonical" href="https://rank.example/repositories/github/alice/app"')
    expect(repository_profile.body).to include('name="twitter:image" content="https://rank.example/images/pos.png"')

    expect(english_about.body).to include('<html lang="en">')
    expect(english_about.body).to include('rel="canonical" href="https://rank.example/en/about"')
    expect(english_about.body).to include('property="og:locale" content="en_US"')
  end

  it 'serves internal job progress as a noindex monitor page', :aggregate_failures do
    ENV['DATABASE_URL'] = "sqlite://#{seed_running_database}"

    response = Rack::MockRequest.new(described_class).get('/internal/jobs')

    expect(response.status).to eq(200)
    expect(response.content_type).to include('text/html')
    expect(response['X-Robots-Tag']).to eq('noindex')
    expect(response.body).to include('<title>Job monitor</title>')
    expect(response.body).to include('noindex,nofollow')
    expect(response.body).to include('2026-04-01 to 2026-05-01')
    expect(response.body).to include('CEST')
    expect(response.body).to include('Candidate queue')
    expect(response.body).to include('Total discovered candidates')
    expect(response.body).to include('Stored snapshot')
    expect(response.body).to include('Users stored for the month')
    expect(response.body).to include('Changes since this run started')
    expect(response.body).to include('Repositories stored in this run')
    expect(response.body).to include('Last checked candidate')
    expect(response.body).to include('Last stored repository')
    expect(response.body).to include('API requests per minute')
    expect(response.body).to include('Last monitor events')
    expect(response.body).to include('Last error logs')
    expect(response.body).to include('monitor-axis-label')
  end

  def seed_database
    path = empty_database
    database = bootstrapped_database(path)
    run_repository = snapshot_run_repository(database)
    snapshot_repository = snapshot_repository(database)
    older_period = PolishOpenSourceRank::Shared::Domain::Period.parse('2025-12')
    older_run_id = run_repository.create(older_period)
    snapshot_repository.upsert_user(user_attributes)
    snapshot_repository.record_user_stats(user_stats(older_period))
    snapshot_repository.upsert_repository(repository_attributes)
    snapshot_repository.record_repository_stats(repository_stats(older_period))
    seed_extra_ranked_records(snapshot_repository, older_period)
    run_repository.finish(older_run_id)

    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    run_id = run_repository.create(period)

    snapshot_repository.upsert_user(user_attributes)
    snapshot_repository.record_user_stats(user_stats(period))
    snapshot_repository.upsert_repository(repository_attributes)
    snapshot_repository.record_repository_stats(repository_stats(period))
    seed_extra_ranked_records(snapshot_repository, period)
    run_repository.finish(run_id)
    path
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
      public_activity_count: 8
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

  def cookie_header(response)
    Array(response['Set-Cookie']).map { |cookie| cookie.split(';').first }.join('; ')
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

  def reset_app_memoized_dependencies
    %i[
      @database
      @show_rankings
      @show_ranking_detail
      @list_editions
      @show_user_profile
      @show_repository_profile
      @render_badge
      @resolve_period
      @show_job_progress
      @show_discord_panel
      @connect_discord_account
      @register_public_github_profile
      @cache_revision_read_model
      @ranking_read_model
      @edition_read_model
      @profile_read_model
      @public_profile_repository
      @contributor_access_read_model
      @discord_connection_repository
      @job_progress_read_model
    ].each do |ivar|
      described_class.remove_instance_variable(ivar) if described_class.instance_variable_defined?(ivar)
    end
  end

  def stub_discord_invite_response(body)
    response = Net::HTTPOK.new('1.1', '200', 'OK')
    response.body = body
    response.instance_variable_set(:@read, true)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  # rubocop:disable Lint/ConstantDefinitionInBlock
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
      raise PolishOpenSourceRank::Web::Auth::DiscordGateway::Error
    end

    def create_invite(channel_id:)
      raise PolishOpenSourceRank::Web::Auth::DiscordGateway::Error, channel_id
    end
  end

  class FailingWelcomeDiscordGateway < FakeDiscordGateway
    def post_welcome_message(**_attributes)
      raise PolishOpenSourceRank::Web::Auth::DiscordGateway::Error
    end
  end

  class FailingMemberSyncDiscordGateway < FakeDiscordGateway
    def sync_member(**_attributes)
      raise PolishOpenSourceRank::Web::Auth::DiscordGateway::Error
    end
  end

  class FailingDiscordOAuthClient < FakeDiscordOAuthClient
    def exchange_code(code:, redirect_uri:)
      super
      raise PolishOpenSourceRank::Web::Auth::DiscordOAuthClient::Error, '400 invalid_grant'
    end
  end
  # rubocop:enable Lint/ConstantDefinitionInBlock
end

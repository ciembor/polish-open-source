# frozen_string_literal: true

class OAuthFlowCallable
  attr_accessor :result, :error
  attr_reader :calls

  def initialize(result = nil)
    @result = result
    @calls = []
  end

  def call(*args, **kwargs)
    calls << { args: args, kwargs: kwargs }
    raise error if error

    result
  end
end

RSpec.describe PolishOpenSourceRank::Web::Auth::OAuthLoginFlow do
  before do
    @period_start = Date.new(2026, 5, 1)
    @github_user = { 'id' => 1, 'login' => 'alice', 'location' => 'Krakow, Poland' }
    @discord_user = { 'id' => 'discord-1', 'username' => 'alice-discord' }
    @existing_profile = { platform: 'github', login: 'alice', github_id: 1 }
    @registered_profile = { platform: 'github', login: 'alice', github_id: 1 }
    @current_user = { platform: 'github', login: 'alice', github_id: 1 }
    @public_github_profile = OAuthFlowCallable.new(@existing_profile)
    @register_public_github_profile = OAuthFlowCallable.new(@registered_profile)
    @connect_discord_account = OAuthFlowCallable.new
    @github_oauth_client = github_oauth_client
    @discord_oauth_client = discord_oauth_client
    @flow = described_class.new(
      github_oauth_client: @github_oauth_client,
      discord_oauth_client: @discord_oauth_client,
      public_github_profile: @public_github_profile,
      register_public_github_profile: @register_public_github_profile,
      connect_discord_account: @connect_discord_account
    )
  end

  it 'builds provider authorization URLs through the OAuth clients' do
    expect(@flow.github_authorize_url(state: 'state-1', redirect_uri: 'https://rank/auth/github/callback')).to eq(
      'https://github.test/oauth'
    )
    expect(@flow.discord_authorize_url(state: 'state-2', redirect_uri: 'https://rank/auth/discord/callback')).to eq(
      'https://discord.test/oauth'
    )
  end

  it 'finishes GitHub login with an existing public profile' do
    result = @flow.finish_github(callback: github_callback, period_start: @period_start)

    expect(result.profile).to eq(@existing_profile)
    expect(result.session).to eq(platform: 'github', login: 'alice', github_id: 1)
    expect(result).not_to be_missing_location
    expect(@register_public_github_profile.calls).to be_empty
  end

  it 'registers eligible GitHub users that are not public yet' do
    @public_github_profile.result = nil

    result = @flow.finish_github(callback: github_callback, period_start: @period_start)

    expect(result.profile).to eq(@registered_profile)
    expect(@register_public_github_profile.calls).to contain_exactly(
      args: [],
      kwargs: { github_profile: @github_user, period_start: @period_start }
    )
  end

  it 'reports GitHub users without an eligible location without building a session' do
    @public_github_profile.result = nil
    @register_public_github_profile.error =
      PolishOpenSourceRank::Contexts::Publication::Application::RegisterPublicGitHubProfile::IneligibleLocation

    result = @flow.finish_github(callback: github_callback, period_start: @period_start)

    expect(result).to be_missing_location
    expect(result.session).to be_nil
  end

  it 'finishes Discord login by connecting the current user account' do
    result = @flow.finish_discord(discord_login)

    expect(result).to be_success
    expect(@connect_discord_account.calls).to contain_exactly(
      args: [],
      kwargs: {
        current_user: @current_user,
        discord_user: @discord_user,
        access_token: 'discord-token',
        period_start: @period_start,
        welcome_channel_id: 'welcome-channel'
      }
    )
  end

  it 'classifies rejected Discord OAuth callbacks separately from sync failures' do
    allow(@discord_oauth_client).to receive(:exchange_code).and_raise(
      PolishOpenSourceRank::Web::Auth::DiscordOAuthClient::Error
    )

    result = @flow.finish_discord(discord_login)

    expect(result.error).to eq('oauth')
  end

  it 'lets missing public profiles stay visible to the web adapter as a 404 decision' do
    @connect_discord_account.error =
      PolishOpenSourceRank::Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound

    expect do
      @flow.finish_discord(discord_login)
    end.to raise_error(
      PolishOpenSourceRank::Contexts::Community::Application::ConnectDiscordAccount::PublicProfileNotFound
    )
  end

  it 'classifies unexpected Discord account sync errors as retryable sync failures' do
    allow(@discord_oauth_client).to receive(:user).and_raise(StandardError)

    result = @flow.finish_discord(discord_login)

    expect(result.error).to eq('sync')
  end

  def github_oauth_client
    instance_double(
      PolishOpenSourceRank::Web::Auth::GitHubOAuthClient,
      authorize_url: 'https://github.test/oauth',
      exchange_code: 'github-token',
      user: @github_user
    )
  end

  def discord_oauth_client
    instance_double(
      PolishOpenSourceRank::Web::Auth::DiscordOAuthClient,
      authorize_url: 'https://discord.test/oauth',
      exchange_code: { 'access_token' => 'discord-token' },
      user: @discord_user
    )
  end

  def github_callback
    described_class::Callback.new(code: 'github-code', redirect_uri: 'https://rank/auth/github/callback')
  end

  def discord_callback
    described_class::Callback.new(code: 'discord-code', redirect_uri: 'https://rank/auth/discord/callback')
  end

  def discord_login
    described_class::DiscordLogin.new(
      current_user: @current_user,
      callback: discord_callback,
      period_start: @period_start,
      welcome_channel_id: 'welcome-channel'
    )
  end
end

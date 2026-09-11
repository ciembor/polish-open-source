# frozen_string_literal: true

class ManualInviteProfileSource
  attr_reader :requested_login

  def platform
    'github'
  end

  def user(login)
    @requested_login = login
    PolishOpenSourceRank::Contexts::Ranking::Domain::SourceContributor.new(
      source_id: 40,
      login: login,
      html_url: "https://github.com/#{login}"
    )
  end
end

class ManualInviteGateway
  attr_reader :channel_id

  def create_invite(channel_id:)
    @channel_id = channel_id
    { code: 'manual-guest', url: 'https://discord.gg/manual-guest' }
  end
end

class ManualInviteRepository
  attr_reader :recorded

  def record(**attributes)
    @recorded = attributes
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::InviteDiscordGuest do
  it 'creates and records a one-use Discord invite for a GitHub profile' do
    profile_source = ManualInviteProfileSource.new
    invite_gateway = ManualInviteGateway.new
    invite_repository = ManualInviteRepository.new

    result = described_class.new(
      profile_source: profile_source,
      invite_gateway: invite_gateway,
      invite_repository: invite_repository,
      invite_channel_id: 'invite-channel'
    ).call(login: 'guest', invited_by: 'maciej')

    expect(profile_source.requested_login).to eq('guest')
    expect(invite_gateway.channel_id).to eq('invite-channel')
    expect(invite_repository.recorded).to include(invited_by: 'maciej')
    expect(invite_repository.recorded.fetch(:profile)).to include(platform: 'github', source_id: 40, login: 'guest')
    expect(result.invite).to eq(code: 'manual-guest', url: 'https://discord.gg/manual-guest')
  end
end

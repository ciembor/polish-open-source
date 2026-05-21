# frozen_string_literal: true

class ProfileReadModel
  def user_profile(*) = nil
end

class AccessReadModel
  def discord_access(*, **) = nil
end

class RoleMap
  def role_ids(*) = []

  def managed_role_ids = []
end

class RecordingConnectionRepository
  attr_reader :connection

  def upsert_discord_connection(**attributes)
    @connection = attributes
  end
end

class RecordingMemberGateway
  attr_reader :synced, :welcome

  def sync_member(**attributes)
    @synced = attributes
  end

  def post_welcome_message(**attributes)
    @welcome = attributes
  end
end

class FailingWelcomeMemberGateway < RecordingMemberGateway
  def post_welcome_message(**_attributes)
    raise StandardError
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::ConnectDiscordAccount do
  # rubocop:disable RSpec/ExampleLength
  it 'links Discord, syncs member roles, and posts a welcome message' do
    profile_read_model = instance_double(
      ProfileReadModel,
      user_profile: { platform: 'github', login: 'alice', github_id: 1, period_start: '2026-04-01' }
    )
    access_read_model = instance_double(
      AccessReadModel,
      discord_access: { role_keys: %w[top city], country_rank: 1, city_rank: 1 }
    )
    connection_repository = RecordingConnectionRepository.new
    member_gateway = RecordingMemberGateway.new
    role_map = instance_double(RoleMap, role_ids: %w[role-top role-city],
                                        managed_role_ids: %w[role-top role-city old])

    result = described_class.new(
      profile_read_model: profile_read_model,
      connection_repository: connection_repository,
      access_read_model: access_read_model,
      member_gateway: member_gateway,
      role_map: role_map
    ).call(
      current_user: { platform: 'github', login: 'alice' },
      discord_user: { 'id' => 'discord-1', 'username' => 'alice-discord', 'global_name' => 'Alice Discord' },
      access_token: 'access-token',
      period_start: '2026-04-01',
      welcome_channel_id: 'welcome'
    )

    expect(result.role_ids).to eq(%w[role-top role-city])
    expect(connection_repository.connection).to include(discord_username: 'Alice Discord')
    expect(member_gateway.synced).to include(github_login: 'alice', desired_role_ids: %w[role-top role-city])
    expect(member_gateway.welcome).to include(channel_id: 'welcome', role_ids: %w[role-top role-city])
  end

  it 'rejects Discord connection when the current user is no longer ranked' do
    use_case = described_class.new(
      profile_read_model: instance_double(ProfileReadModel, user_profile: nil),
      connection_repository: RecordingConnectionRepository.new,
      access_read_model: instance_double(AccessReadModel),
      member_gateway: RecordingMemberGateway.new,
      role_map: instance_double(RoleMap)
    )

    expect do
      use_case.call(
        current_user: { platform: 'github', login: 'missing' },
        discord_user: { 'id' => 'discord-1', 'username' => 'missing' },
        access_token: 'access-token',
        period_start: '2026-04-01',
        welcome_channel_id: 'welcome'
      )
    end.to raise_error(described_class::ProfileNotFound)
  end

  it 'keeps Discord login successful when welcome delivery fails' do
    use_case = described_class.new(
      profile_read_model: instance_double(
        ProfileReadModel,
        user_profile: { platform: 'github', login: 'alice', github_id: 1, period_start: '2026-04-01' }
      ),
      connection_repository: RecordingConnectionRepository.new,
      access_read_model: instance_double(AccessReadModel, discord_access: { role_keys: [] }),
      member_gateway: FailingWelcomeMemberGateway.new,
      role_map: instance_double(RoleMap, role_ids: [], managed_role_ids: [])
    )

    expect do
      use_case.call(
        current_user: { platform: 'github', login: 'alice' },
        discord_user: { 'id' => 'discord-1', 'username' => 'alice-discord' },
        access_token: 'access-token',
        period_start: '2026-04-01',
        welcome_channel_id: 'welcome'
      )
    end.not_to raise_error
  end
  # rubocop:enable RSpec/ExampleLength
end

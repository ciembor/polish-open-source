# frozen_string_literal: true

class ProfileReadModel
  def user_profile(*) = nil
end

class AccessReadModel
  def discord_access(*, **) = nil
end

class RecordingConnectionRepository
  attr_reader :connection

  def upsert_discord_connection(**attributes)
    @connection = attributes
  end
end

class RecordingSyncJobRepository
  attr_reader :oauth_sync

  def request_oauth_sync(**attributes)
    @oauth_sync = attributes
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::ConnectDiscordAccount do
  it 'links Discord, syncs member roles, and posts a welcome message' do
    profile_read_model = instance_double(
      ProfileReadModel,
      user_profile: { platform: 'github', login: 'alice', source_id: 1, period_start: '2026-04-01' }
    )
    access_read_model = instance_double(
      AccessReadModel,
      discord_access: { role_keys: %w[top city], country_rank: 1, city_rank: 1 }
    )
    connection_repository = RecordingConnectionRepository.new
    sync_job_repository = RecordingSyncJobRepository.new

    result = described_class.new(
      profile_read_model: profile_read_model,
      connection_repository: connection_repository,
      sync_job_repository: sync_job_repository,
      access_read_model: access_read_model
    ).call(
      current_user: { platform: 'github', login: 'alice' },
      discord_user: { 'id' => 'discord-1', 'username' => 'alice-discord', 'global_name' => 'Alice Discord' },
      access_token: 'access-token',
      period_start: '2026-04-01',
      welcome_channel_id: 'welcome'
    )

    expect_connected_discord(result, connection_repository, sync_job_repository)
  end

  def expect_connected_discord(result, connection_repository, sync_job_repository)
    expect(result.role_ids).to eq([])
    expect(result.sync_status).to eq('pending')
    expect(connection_repository.connection).to include(discord_username: 'Alice Discord')
    expect(sync_job_repository.oauth_sync).to include(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice Discord',
      access_token: 'access-token',
      welcome_channel_id: 'welcome'
    )
  end

  it 'rejects Discord connection when the current user has no public profile' do
    use_case = described_class.new(
      profile_read_model: instance_double(ProfileReadModel, user_profile: nil),
      connection_repository: RecordingConnectionRepository.new,
      sync_job_repository: RecordingSyncJobRepository.new,
      access_read_model: instance_double(AccessReadModel)
    )

    expect do
      use_case.call(
        current_user: { platform: 'github', login: 'missing' },
        discord_user: { 'id' => 'discord-1', 'username' => 'missing' },
        access_token: 'access-token',
        period_start: '2026-04-01',
        welcome_channel_id: 'welcome'
      )
    end.to raise_error(described_class::PublicProfileNotFound)
  end

  it 'links Discord without ranking roles for public profiles outside the current ranking' do
    use_case = described_class.new(
      profile_read_model: instance_double(
        ProfileReadModel,
        user_profile: { platform: 'github', login: 'alice', source_id: 1, period_start: nil }
      ),
      connection_repository: RecordingConnectionRepository.new,
      sync_job_repository: RecordingSyncJobRepository.new,
      access_read_model: instance_double(AccessReadModel, discord_access: { role_keys: [] })
    )

    expect do
      use_case.call(
        current_user: { platform: 'github', login: 'alice' },
        discord_user: { 'id' => 'discord-1', 'username' => 'alice-discord' },
        access_token: 'access-token',
        period_start: nil,
        welcome_channel_id: 'welcome'
      )
    end.not_to raise_error
  end
end

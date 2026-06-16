# frozen_string_literal: true

class ProfileReadModelForSync
  def user_profile(*) = { login: 'alice', repositories: [] }
end

class AccessReadModelForSync
  def discord_access(*) = { role_keys: %w[top] }
end

class RoleMapForSync
  Prepared = Struct.new(:managed_role_ids, :role_ids_by_key, keyword_init: true) do
    def role_ids(keys)
      keys.filter_map { |key| role_ids_by_key.fetch(key, nil) }
    end
  end

  def prepare(*)
    Prepared.new(managed_role_ids: %w[role-top role-old], role_ids_by_key: { 'top' => 'role-top' })
  end

  def managed_role_ids(prepared:) = prepared.managed_role_ids
end

class MemberGatewayForSync
  attr_reader :synced, :joined, :welcome

  def sync_member(**attributes)
    @synced = attributes
  end

  def sync_joined_member(**attributes)
    @joined = attributes
  end

  def post_welcome_message(**attributes)
    @welcome = attributes
  end
end

class FailingMemberGatewayForSync < MemberGatewayForSync
  def sync_joined_member(**)
    raise StandardError, 'discord unavailable'
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::SyncDiscordConnection do
  it 'runs member sync and welcome jobs from the outbox' do
    repository = seeded_repository
    gateway = MemberGatewayForSync.new
    repository.request_oauth_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice',
      access_token: 'access-token',
      welcome_channel_id: 'welcome'
    )

    use_case(repository, gateway).call(period_start: '2026-04-01')

    expect(gateway.synced).to include(
      discord_user_id: 'discord-1',
      access_token: 'access-token',
      github_login: 'alice',
      desired_role_ids: %w[role-top],
      managed_role_ids: %w[role-top role-old]
    )
    expect(gateway.welcome).to include(channel_id: 'welcome', discord_user_id: 'discord-1', role_ids: %w[role-top])
    expect(repository.sync_status('github', 1)).to eq('synced')
  end

  it 'syncs only the requested connected account' do
    repository = seeded_repository
    gateway = MemberGatewayForSync.new
    repository.request_oauth_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice',
      access_token: 'access-token',
      welcome_channel_id: nil
    )
    insert_user(2, 'bob')
    repository.request_oauth_sync(
      platform: 'github',
      source_id: 2,
      discord_user_id: 'discord-2',
      discord_username: 'Bob',
      access_token: 'bob-token',
      welcome_channel_id: nil
    )

    use_case(repository, gateway).call_for(platform: 'github', source_id: 1, period_start: '2026-04-01')

    expect(gateway.synced).to include(discord_user_id: 'discord-1', access_token: 'access-token')
    expect(repository.sync_status('github', 1)).to eq('synced')
    expect(repository.sync_status('github', 2)).to eq('pending')
  end

  it 'retries invite sync failures and marks repeated failures as failed' do
    repository = seeded_repository
    repository.request_invite_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice'
    )
    use_case = use_case(repository, FailingMemberGatewayForSync.new)

    2.times { use_case.call(period_start: '2026-04-01') }
    expect(repository.sync_status('github', 1)).to eq('retryable')

    use_case.call(period_start: '2026-04-01')
    expect(repository.sync_status('github', 1)).to eq('failed')
  end

  def use_case(repository, gateway)
    described_class.new(
      sync_job_repository: repository,
      profile_read_model: ProfileReadModelForSync.new,
      access_read_model: AccessReadModelForSync.new,
      member_gateway: gateway,
      role_map: RoleMapForSync.new
    )
  end

  def seeded_repository
    @database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    )
    @database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    insert_user(1, 'alice')
    PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository.new(@database)
  end

  def insert_user(source_id, login)
    @database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', source_id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
  end
end

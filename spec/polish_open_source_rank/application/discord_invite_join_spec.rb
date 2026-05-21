# frozen_string_literal: true

class LegacyDiscordStore
  def discord_invite_profile(*) = nil

  def upsert_discord_connection(**) = nil

  def discord_access(*, **) = nil
end

RSpec.describe PolishOpenSourceRank::Application::DiscordInviteJoin do
  # rubocop:disable RSpec/ExampleLength
  around do |example|
    old_env = ENV.to_h
    ENV['DISCORD_ROLE_TOP_10_PL'] = 'role-top-10'
    ENV['DISCORD_ROLE_TOP_100_PL'] = 'role-top-100'
    ENV['DISCORD_ROLE_TOP_100_CITY_KRAKOW'] = 'role-krakow'
    ENV['DISCORD_ROLE_BADGE_TOP_1'] = 'role-gold'
    example.run
  ensure
    ENV.replace(old_env)
  end

  it 'syncs a Discord member from a used invite code mapped to a ranked profile', :aggregate_failures do
    setup = migrated_database
    database = setup.fetch(:database)
    invite_repository = PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database)
    connection_repository =
      PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database)
    access_read_model =
      PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    store = PolishOpenSourceRank::Infrastructure::SQLiteStore.new(setup.fetch(:path))
    run_id = store.create_run(period)
    store.upsert_user(user_attributes)
    store.record_user_stats(user_stats(period))
    invite_repository.record(
      platform: 'github',
      user_github_id: 1,
      code: 'invite-for-alice',
      url: 'https://discord.gg/invite-for-alice'
    )
    store.finish_run(run_id)
    gateway = GatewaySpy.new

    synced = described_class.new(
      invite_repository: invite_repository,
      connection_repository: connection_repository,
      access_read_model: access_read_model,
      discord_gateway: gateway,
      discord_role_map: PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new
    ).call(invite_code: 'invite-for-alice', discord_user_id: 'discord-1', discord_username: 'Alice D')

    expect(synced).to be(true)
    expect(connection_repository.find('github', 1)).to include(
      discord_user_id: 'discord-1',
      discord_username: 'Alice D'
    )
    expect(gateway.synced).to include(discord_user_id: 'discord-1', github_login: 'alice')
    expect(gateway.synced.fetch(:desired_role_ids)).to contain_exactly(
      'role-top-10',
      'role-top-100',
      'role-krakow',
      'role-gold'
    )
  end
  # rubocop:enable RSpec/ExampleLength

  it 'ignores unknown invite codes' do
    database = migrated_database.fetch(:database)
    gateway = GatewaySpy.new

    synced = described_class.new(
      invite_repository: PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database),
      connection_repository:
        PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database),
      access_read_model:
        PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database),
      discord_gateway: gateway,
      discord_role_map: PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new
    ).call(invite_code: 'missing', discord_user_id: 'discord-1', discord_username: 'Alice D')

    expect(synced).to be(false)
    expect(gateway.synced).to be_nil
  end

  it 'keeps compatibility with the legacy store-shaped interface' do
    gateway = GatewaySpy.new
    store = instance_double(LegacyDiscordStore)
    allow(store).to receive(:discord_invite_profile).with('invite-for-alice').and_return(
      platform: 'github',
      github_id: 1,
      login: 'alice'
    )
    allow(store).to receive(:upsert_discord_connection).with(
      platform: 'github',
      user_github_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice D'
    )
    allow(store).to receive(:discord_access).with('github', 1, period_start: nil).and_return(role_keys: [])

    synced = described_class.new(
      store: store,
      discord_gateway: gateway,
      discord_role_map: PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordRoleMap.new
    ).call(invite_code: 'invite-for-alice', discord_user_id: 'discord-1', discord_username: 'Alice D')

    expect(synced).to be(true)
    expect(gateway.synced).to include(discord_user_id: 'discord-1', github_login: 'alice')
  end

  def user_attributes
    {
      github_id: 1,
      login: 'alice',
      name: 'Alice Example',
      location_raw: 'Krakow, Poland',
      city: 'Kraków',
      country: 'Poland',
      email: 'alice@example.com',
      homepage: 'https://alice.example',
      html_url: 'https://github.com/alice',
      avatar_url: nil
    }
  end

  def user_stats(period)
    {
      period_start: period.start_date.to_s,
      user_github_id: 1,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland',
      public_repo_count: 1,
      total_stars: 123,
      monthly_stars_delta: 4,
      public_activity_count: 5
    }
  end

  def migrated_database
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    migration = PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
      database,
      PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
    )
    migration.needed? ? migration.run : database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    { path: path, database: database }
  end

  # rubocop:disable Lint/ConstantDefinitionInBlock
  class GatewaySpy
    attr_reader :synced

    def sync_joined_member(**attributes)
      @synced = attributes
    end
  end
  # rubocop:enable Lint/ConstantDefinitionInBlock
end

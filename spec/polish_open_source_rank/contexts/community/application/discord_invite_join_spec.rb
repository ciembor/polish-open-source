# frozen_string_literal: true

class SyncJobRepositorySpy
  attr_reader :invite_sync

  def request_invite_sync(**attributes)
    @invite_sync = attributes
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Community::Application::DiscordInviteJoin do
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
    dependencies = ranked_invite_dependencies
    sync_job_repository = SyncJobRepositorySpy.new

    synced = described_class.new(
      invite_repository: dependencies.fetch(:invite_repository),
      connection_repository: dependencies.fetch(:connection_repository),
      sync_job_repository: sync_job_repository
    ).call(invite_code: 'invite-for-alice', discord_user_id: 'discord-1', discord_username: 'Alice D')

    expect(synced).to be(true)
    expect(dependencies.fetch(:connection_repository).find('github', 1)).to include(
      discord_user_id: 'discord-1',
      discord_username: 'Alice D'
    )
    expect(sync_job_repository.invite_sync).to include(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice D'
    )
  end

  def ranked_invite_dependencies
    database = migrated_database.fetch(:database)
    period = PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04')
    invite_repository = invite_repository(database)
    run_repository = snapshot_run_repository(database)
    snapshot_repository = snapshot_repository(database)
    run_id = run_repository.create(period)
    snapshot_repository.upsert_user(user_attributes)
    snapshot_repository.record_user_stats(user_stats(period))
    invite_repository.record(
      platform: 'github',
      source_id: 1,
      code: 'invite-for-alice',
      url: 'https://discord.gg/invite-for-alice'
    )
    run_repository.finish(run_id)
    {
      invite_repository: invite_repository,
      connection_repository: connection_repository(database),
      sync_job_repository: PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository.new(database)
    }
  end

  def invite_repository(database)
    PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database)
  end

  def connection_repository(database)
    PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database)
  end

  def access_read_model(database)
    PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteContributorAccessReadModel.new(database)
  end

  def snapshot_run_repository(database)
    PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository.new(database)
  end

  def snapshot_repository(database)
    PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRepository.new(database)
  end

  it 'ignores unknown invite codes' do
    database = migrated_database.fetch(:database)

    synced = described_class.new(
      invite_repository: PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository.new(database),
      connection_repository:
        PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository.new(database),
      sync_job_repository:
        PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository.new(database)
    ).call(invite_code: 'missing', discord_user_id: 'discord-1', discord_username: 'Alice D')

    expect(synced).to be(false)
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
      merged_pull_requests_count: 5
    }
  end

  def migrated_database
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration.new(
      database,
      PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql
    ).bootstrap!
    { database: database }
  end
end

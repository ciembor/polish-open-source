# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Composition do
  it 'builds default Discord gateway and sync use case through the community context' do
    database_path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: database_path,
      public_database_path: database_path,
      discord_bot_token: 'bot-token',
      discord_guild_id: 'guild-1',
      http_timeouts: { open_timeout: 1, read_timeout: 2, write_timeout: 3 }
    )

    composition = described_class.new(configuration: configuration)

    expect(composition.community.discord_gateway).to be_a(
      PolishOpenSourceRank::Contexts::Community::Infrastructure::Discord::DiscordApiGateway
    )
    expect(composition.community.sync_discord_connection).to be_a(
      PolishOpenSourceRank::Contexts::Community::Application::SyncDiscordConnection
    )
  end

  it 'exposes use cases through bounded web contexts', :aggregate_failures do
    database_path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: database_path,
      public_database_path: database_path,
      discord_bot_token: 'bot-token',
      discord_guild_id: 'guild-1',
      http_timeouts: { open_timeout: 1, read_timeout: 2, write_timeout: 3 }
    )

    composition = described_class.new(configuration: configuration)

    expect(composition.publication.show_rankings).to be_a(
      PolishOpenSourceRank::Contexts::Publication::Application::ShowRankings
    )
    expect(composition.packages.show_package_index).to be_a(
      PolishOpenSourceRank::Contexts::Packages::Application::ShowPackageIndex
    )
    expect(composition.languages.show_language_index).to be_a(
      PolishOpenSourceRank::Contexts::Languages::Application::ShowLanguageIndex
    )
    expect(composition.operations.show_job_progress).to be_a(
      PolishOpenSourceRank::Contexts::Operations::Application::ShowJobProgress
    )
    expect(composition.sitemap_catalog).to be_a(
      PolishOpenSourceRank::Web::Composition::SitemapCatalog
    )
    expect(composition.development).to be_a(
      PolishOpenSourceRank::Web::Composition::DeveloperAccess
    )
  end

  it 'opens a configured public database as a read-only snapshot' do
    working_path = File.join(Dir.mktmpdir, 'working.sqlite3')
    public_path = File.join(Dir.mktmpdir, 'public.sqlite3')
    writable_public = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(public_path)
    writable_public.execute('CREATE TABLE markers(value TEXT)')
    writable_public.execute('INSERT INTO markers(value) VALUES (?)', ['public'])
    writable_public.close
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: working_path,
      public_database_path: public_path
    )

    public_database = described_class.new(configuration: configuration).public_database

    expect(public_database.fetch_value('PRAGMA query_only')).to eq(1)
    expect(public_database.fetch_value('SELECT value FROM markers')).to eq('public')
    expect do
      public_database.execute('INSERT INTO markers(value) VALUES (?)', ['write'])
    end.to raise_error(Sequel::DatabaseError)
  end

  it 'redacts public profiles in both working and public database files' do
    working_path = seeded_profile_database_path
    public_path = seeded_profile_database_path
    configuration = instance_double(
      PolishOpenSourceRank::Configuration,
      database_path: working_path,
      public_database_path: public_path
    )

    described_class.new(configuration: configuration).publication.delete_public_profile.call(
      platform: 'github',
      source_id: 1
    )

    expect(profile_deleted?(working_path)).to be(true)
    expect(profile_deleted?(public_path)).to be(true)
  end

  def seeded_profile_database_path
    File.join(Dir.mktmpdir, 'profile.sqlite3').tap do |path|
      database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
      database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      database.execute(
        'INSERT INTO users(platform, github_id, login, name, html_url, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
        ['github', 1, 'alice', 'Alice', 'https://github.com/alice', '2026-06-01T00:00:00Z']
      )
      database.close
    end
  end

  def profile_deleted?(path)
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    database.dataset(:users).where(platform: 'github', github_id: 1).first.fetch(:profile_deleted) == 1
  ensure
    database&.close
  end
end

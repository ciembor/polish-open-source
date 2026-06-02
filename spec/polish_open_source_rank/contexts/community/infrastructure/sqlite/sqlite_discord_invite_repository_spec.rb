# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordInviteRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'records one active Discord invite per ranking identity' do
    seed_user

    repository.record(platform: 'github', source_id: 1, code: 'abc', url: 'https://discord.gg/abc')
    repository.record(platform: 'github', source_id: 1, code: 'def', url: 'https://discord.gg/def')

    expect(repository.find('github', 1)).to include(
      code: 'def',
      url: 'https://discord.gg/def',
      created_at: '2026-05-01T12:00:00Z'
    )
    expect(repository.profile_for_code('def')).to include(platform: 'github', source_id: 1, login: 'alice')
  end

  it 'retries as an update when the invite insert races with another writer' do
    initial_scope = object_double(update_scope_contract)
    dataset = object_double(dataset_contract)
    database = object_double(database_contract)
    repository = described_class.new(database, clock: clock)

    allow(database).to receive(:dataset).with(:discord_invites).and_return(dataset)
    allow(database).to receive(:transaction).and_yield
    allow(database).to receive(:write).and_yield
    allow(dataset).to receive(:where).with(platform: 'github', user_github_id: 1).and_return(initial_scope)
    allow(initial_scope).to receive(:update).with(
      {
        code: 'def',
        url: 'https://discord.gg/def',
        created_at: '2026-05-01T12:00:00Z'
      }
    ).and_return(0, 1)
    allow(dataset).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation, 'race')

    repository.record(platform: 'github', source_id: 1, code: 'def', url: 'https://discord.gg/def')

    expect(initial_scope).to have_received(:update).with(
      {
        code: 'def',
        url: 'https://discord.gg/def',
        created_at: '2026-05-01T12:00:00Z'
      }
    ).twice
  end

  def seed_user
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
  end

  def update_scope_contract
    Object.new.tap do |scope|
      def scope.update(_attributes); end
    end
  end

  def dataset_contract
    Object.new.tap do |dataset|
      def dataset.where(_conditions); end
      def dataset.insert(_attributes); end
    end
  end

  def database_contract
    Object.new.tap do |database|
      def database.dataset(_table); end
      def database.transaction; end
      def database.write; end
    end
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordConnectionRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'upserts Discord connections by ranking identity' do
    seed_user

    repository.upsert(
      platform: 'github',
      user_github_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice'
    )
    repository.upsert(
      platform: 'github',
      user_github_id: 1,
      discord_user_id: 'discord-2',
      discord_username: 'Alice D'
    )

    expect(repository.find('github', 1)).to include(
      discord_user_id: 'discord-2',
      discord_username: 'Alice D',
      updated_at: '2026-05-01T12:00:00Z'
    )
  end

  # rubocop:disable RSpec/ExampleLength
  it 'retries as an update when the insert races with another writer' do
    initial_scope = double('initial scope')
    dataset = double('dataset')
    database = double('database')
    repository = described_class.new(database, clock: clock)

    allow(database).to receive(:dataset).with(:discord_connections).and_return(dataset)
    allow(database).to receive(:transaction).and_yield
    allow(dataset).to receive(:where).with(platform: 'github', user_github_id: 1).and_return(initial_scope)
    allow(initial_scope).to receive(:update).with(
      {
        discord_user_id: 'discord-2',
        discord_username: 'Alice D',
        updated_at: '2026-05-01T12:00:00Z'
      }
    ).and_return(0, 1)
    allow(dataset).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation, 'race')

    repository.upsert(
      platform: 'github',
      user_github_id: 1,
      discord_user_id: 'discord-2',
      discord_username: 'Alice D'
    )

    expect(initial_scope).to have_received(:update).with(
      {
        discord_user_id: 'discord-2',
        discord_username: 'Alice D',
        updated_at: '2026-05-01T12:00:00Z'
      }
    ).twice
  end
  # rubocop:enable RSpec/ExampleLength

  def seed_user
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteDiscordSyncJobRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      sqlite.execute(
        'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
        ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
      )
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'stores idempotent OAuth sync jobs and exposes aggregate status' do
    request_oauth_sync
    request_oauth_sync(discord_username: 'Alice D')

    expect(repository.pending(limit: 10).map { |job| job.fetch(:action_kind) }).to contain_exactly(
      'member_sync',
      'welcome_message'
    )
    expect(repository.sync_status('github', 1)).to eq('pending')
    expect(repository.pending(limit: 1).first).to include(discord_username: 'Alice D', login: 'alice', source_id: 1)
  end

  it 'moves jobs through retryable, failed, and synced states' do
    repository.request_invite_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice'
    )
    job = repository.pending.first

    repository.mark_retryable(job, StandardError.new('temporary'))
    retryable = repository.pending.first
    expect(repository.sync_status('github', 1)).to eq('retryable')
    expect(retryable).to include(status: 'retryable', attempts: 1, error: 'temporary')

    repository.mark_failed(retryable, StandardError.new('broken'))
    expect(repository.sync_status('github', 1)).to eq('failed')

    repository.mark_synced(retryable)
    expect(repository.sync_status('github', 1)).to eq('synced')
    expect(repository.pending).to be_empty
  end

  it 'returns no status when a profile has no sync job' do
    expect(repository.sync_status('github', 1)).to be_nil
  end

  it 'retries as an update when the job insert races with another writer' do
    scope = double('scope')
    dataset = double('dataset')
    database = double('database')
    repository = described_class.new(database, clock: clock)

    allow(database).to receive(:transaction).and_yield
    allow(database).to receive(:dataset).with(:discord_sync_jobs).and_return(dataset)
    allow(dataset).to receive(:where).and_return(scope)
    allow(scope).to receive(:update).and_return(0, 1)
    allow(dataset).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation, 'race')

    repository.request_invite_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: 'Alice'
    )

    expect(scope).to have_received(:update).twice
  end

  def request_oauth_sync(discord_username: 'Alice')
    repository.request_oauth_sync(
      platform: 'github',
      source_id: 1,
      discord_user_id: 'discord-1',
      discord_username: discord_username,
      access_token: 'access-token',
      welcome_channel_id: 'welcome'
    )
  end
end

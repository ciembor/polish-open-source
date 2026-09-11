# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Community::Infrastructure::SQLite::SQLiteManualDiscordInviteRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'records an active manual invite and a minimal GitHub profile' do
    invite = repository.record(
      profile: profile,
      invite: { code: 'manual-guest', url: 'https://discord.gg/manual-guest' },
      invited_by: 'maciej'
    )

    expect(invite).to include(
      platform: 'github',
      user_github_id: 40,
      login: 'guest',
      code: 'manual-guest',
      url: 'https://discord.gg/manual-guest',
      invited_by: 'maciej',
      created_at: '2026-05-01T12:00:00Z'
    )
    expect(repository).to be_invited('github', 40)
    expect(repository.active_invites).to contain_exactly(include(login: 'guest', code: 'manual-guest'))
  end

  it 'retries profile writes as an update when the insert races with another writer' do
    users = object_double(dataset_contract)
    invites = object_double(dataset_contract)
    user_id_scope = object_double(scope_contract, update: 0)
    user_login_scope = object_double(scope_contract)
    invite_scope = object_double(scope_contract, update: 1)
    database = object_double(database_contract)
    repository = described_class.new(database, clock: clock)

    allow(database).to receive(:dataset).with(:users).and_return(users)
    allow(database).to receive(:dataset).with(:manual_discord_invites).and_return(invites)
    allow(database).to receive(:transaction).and_yield
    allow(users).to receive(:where).with(platform: 'github', github_id: 40).and_return(user_id_scope)
    allow(users).to receive(:where).with(platform: 'github', login: 'guest').and_return(user_login_scope)
    allow(users).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation, 'race')
    allow(user_login_scope).to receive(:update)
    allow(invites).to receive(:where).with(platform: 'github', user_github_id: 40).and_return(invite_scope)

    repository.record(profile: profile, invite: invite, invited_by: 'maciej')

    expect(user_login_scope).to have_received(:update).with(
      hash_including(name: 'Guest', html_url: 'https://github.com/guest')
    )
  end

  it 'retries invite writes as an update when the insert races with another writer' do
    users = object_double(dataset_contract)
    invites = object_double(dataset_contract)
    user_scope = object_double(scope_contract, update: 1)
    invite_id_scope = object_double(scope_contract, update: 0)
    invite_login_scope = object_double(scope_contract)
    database = object_double(database_contract)
    repository = described_class.new(database, clock: clock)

    allow(database).to receive(:dataset).with(:users).and_return(users)
    allow(database).to receive(:dataset).with(:manual_discord_invites).and_return(invites)
    allow(database).to receive(:transaction).and_yield
    allow(users).to receive(:where).with(platform: 'github', github_id: 40).and_return(user_scope)
    allow(invites).to receive(:where).with(platform: 'github', user_github_id: 40).and_return(invite_id_scope)
    allow(invites).to receive(:where).with(platform: 'github', login: 'guest').and_return(invite_login_scope)
    allow(invites).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation, 'race')
    allow(invite_login_scope).to receive(:update)

    repository.record(profile: profile, invite: invite, invited_by: 'maciej')

    expect(invite_login_scope).to have_received(:update).with(
      hash_including(code: 'manual-guest', url: 'https://discord.gg/manual-guest')
    )
  end

  def profile
    {
      platform: 'github',
      source_id: 40,
      login: 'guest',
      name: 'Guest',
      location: 'Berlin, Germany',
      email: 'guest@example.com',
      homepage: 'https://guest.example',
      html_url: 'https://github.com/guest',
      avatar_url: 'https://avatars.example/guest.png'
    }
  end

  def invite
    { code: 'manual-guest', url: 'https://discord.gg/manual-guest' }
  end

  def scope_contract
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
    end
  end
end

# frozen_string_literal: true

def github_profile_attributes
  {
    github_id: 1,
    login: 'alice',
    name: 'Alice',
    location_raw: 'Krakow, Poland',
    city: 'Kraków',
    country: 'Poland',
    email: 'alice@example.com',
    homepage: 'https://alice.example',
    html_url: 'https://github.com/alice',
    avatar_url: 'https://avatars.example/alice.png'
  }
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLitePublicProfileRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end

  it 'redacts profile details without removing the stable identity' do
    repository = described_class.new(database, clock: -> { Time.utc(2026, 6, 1) })

    repository.upsert_github_profile(github_profile_attributes)
    deleted = repository.redact_profile(platform: 'github', source_id: 1)

    user = database.dataset(:users).where(platform: 'github', github_id: 1).first
    expect(deleted).to eq(1)
    expect(user).to include(login: 'alice', html_url: 'https://github.com/alice', profile_deleted: 1)
    expect(user).to include(name: nil, location_raw: nil, city: nil, country: nil, email: nil, homepage: nil)
    expect(user).to include(avatar_url: nil, avatar_hidden: 1)
  end

  it 'does not restore redacted profile details from a later public login' do
    repository = described_class.new(database)

    repository.upsert_github_profile(github_profile_attributes)
    repository.redact_profile(platform: 'github', source_id: 1)
    repository.upsert_github_profile(github_profile_attributes.merge(name: 'Restored Alice'))

    user = database.dataset(:users).where(platform: 'github', github_id: 1).first
    expect(user).to include(login: 'alice', html_url: 'https://github.com/alice', profile_deleted: 1)
    expect(user).to include(name: nil, avatar_url: nil)
  end

  it 'replicates profile writes to every configured profile store' do
    first = instance_spy(described_class)
    second = instance_spy(described_class)
    repository = PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::ReplicatedPublicProfileRepository
                 .new([first, second])

    repository.upsert_github_profile(github_profile_attributes)
    repository.redact_profile(platform: 'github', source_id: 1)

    expect(first).to have_received(:upsert_github_profile).with(github_profile_attributes)
    expect(second).to have_received(:upsert_github_profile).with(github_profile_attributes)
    expect(first).to have_received(:redact_profile).with(platform: 'github', source_id: 1)
    expect(second).to have_received(:redact_profile).with(platform: 'github', source_id: 1)
  end

  it 'retries as an update when the insert races with another writer' do
    repository = described_class.new(instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database))
    dataset = instance_double(Sequel::Dataset)
    scoped = instance_double(Sequel::Dataset)
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    allow(repository).to receive_messages(
      users_dataset: dataset,
      timestamp: '2026-05-01T00:00:00Z',
      database: database
    )
    allow(dataset).to receive(:where).and_return(scoped)
    allow(database).to receive(:transaction).and_yield
    allow(database).to receive(:write).and_yield
    allow(scoped).to receive(:first).and_return(nil)
    allow(scoped).to receive(:update).and_return(0, 1)
    allow(dataset).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation)

    repository.upsert_github_profile(github_profile_attributes)

    expect(scoped).to have_received(:update).twice
  end
end

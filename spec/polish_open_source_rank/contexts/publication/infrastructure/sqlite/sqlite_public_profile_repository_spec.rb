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
    allow(scoped).to receive(:update).and_return(0, 1)
    allow(dataset).to receive(:insert).and_raise(Sequel::UniqueConstraintViolation)

    repository.upsert_github_profile(github_profile_attributes)

    expect(scoped).to have_received(:update).twice
  end
end

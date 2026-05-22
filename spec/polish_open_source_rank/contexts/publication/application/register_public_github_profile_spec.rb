# frozen_string_literal: true

class PublicProfileReadModel
  def user_profile(*) = nil
end

class PublicProfileRepository
  attr_reader :attributes

  def upsert_github_profile(attributes)
    @attributes = attributes
  end
end

def polish_location_match
  PolishOpenSourceRank::Contexts::Ranking::Domain::LocationMatch.new(
    city: 'Kraków',
    city_slug: 'krakow',
    country: 'Poland',
    raw: 'Krakow, Poland'
  )
end

def stored_public_profile
  { platform: 'github', login: 'alice', github_id: 1 }
end

def github_public_profile
  {
    'id' => 1,
    'login' => 'alice',
    'name' => 'Alice',
    'location' => 'Krakow, Poland',
    'email' => 'alice@example.com',
    'homepage' => 'https://alice.example',
    'html_url' => 'https://github.com/alice',
    'avatar_url' => 'https://avatars.example/alice.png'
  }
end

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Application::RegisterPublicGitHubProfile do
  it 'returns the existing public profile without rewriting it' do
    profile = { platform: 'github', login: 'alice', github_id: 1 }
    read_model = instance_double(PublicProfileReadModel)
    allow(read_model).to receive(:user_profile).with('github', 'alice', period_start: '2026-04-01').and_return(profile)

    result = described_class.new(
      profile_read_model: read_model,
      profile_repository: PublicProfileRepository.new
    ).call(
      github_profile: { 'id' => 1, 'login' => 'alice' },
      period_start: '2026-04-01'
    )

    expect(result).to eq(profile)
  end

  it 'stores a new public profile when the GitHub location is Polish' do
    repository = PublicProfileRepository.new
    read_model = instance_double(PublicProfileReadModel)
    allow(read_model).to receive(:user_profile).with('github', 'alice', period_start: '2026-04-01').and_return(
      nil,
      stored_public_profile
    )

    classifier = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Domain::LocationClassifier,
      call: polish_location_match
    )

    described_class.new(
      profile_read_model: read_model,
      profile_repository: repository,
      classifier: classifier
    ).call(
      github_profile: github_public_profile,
      period_start: '2026-04-01'
    )

    expect(repository.attributes).to include(
      github_id: 1,
      login: 'alice',
      city: 'Kraków',
      country: 'Poland'
    )
  end

  it 'rejects new GitHub profiles outside the supported location scope' do
    read_model = instance_double(PublicProfileReadModel, user_profile: nil)
    classifier = instance_double(
      PolishOpenSourceRank::Contexts::Ranking::Domain::LocationClassifier,
      call: PolishOpenSourceRank::Contexts::Ranking::Domain::LocationMatch.new(
        city: nil,
        city_slug: nil,
        country: nil,
        raw: 'Berlin, Germany'
      )
    )

    expect do
      described_class.new(
        profile_read_model: read_model,
        profile_repository: PublicProfileRepository.new,
        classifier: classifier
      ).call(
        github_profile: { 'id' => 1, 'login' => 'alice', 'location' => 'Berlin, Germany', 'html_url' => 'x' },
        period_start: '2026-04-01'
      )
    end.to raise_error(described_class::IneligibleLocation)
  end
end

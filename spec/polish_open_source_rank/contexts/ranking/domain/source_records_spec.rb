# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::SourceCandidate do
  let(:contributor_class) { PolishOpenSourceRank::Contexts::Ranking::Domain::SourceContributor }
  let(:repository_class) { PolishOpenSourceRank::Contexts::Ranking::Domain::SourceRepository }

  it 'keeps source candidates typed while preserving explicit hash export' do
    candidate = described_class.new(platform: 'github', source_id: 1, login: 'alice')

    expect(candidate.platform).to eq('github')
    expect(candidate.source_id).to eq(1)
    expect(candidate.login).to eq('alice')
    expect(candidate.identity.platform_key).to eq('github')
    expect(candidate.to_h).to eq(platform: 'github', source_id: 1, login: 'alice')
    expect(candidate).to eq(platform: 'github', source_id: 1, login: 'alice')
    expect(candidate).not_to respond_to(:login=)
  end

  it 'normalizes contributor profile fields behind readers' do
    contributor = contributor_class.new(
      source_id: 1,
      login: 'alice',
      location: 'Kraków, Poland',
      html_url: 'https://github.com/alice'
    )

    expect(contributor.login).to eq('alice')
    expect(contributor.location_evidence).to eq('Kraków, Poland')
    expect(contributor.html_url).to eq('https://github.com/alice')
    expect(contributor.fetch(:missing, 'fallback')).to eq('fallback')
  end

  it 'keeps repository invariants and star replacement inside the object' do
    repository = repository_class.new(
      source_id: 10,
      name: 'app',
      full_name: 'alice/app',
      html_url: 'https://github.com/alice/app',
      fork: false,
      archived: false,
      stars: '42'
    )
    refreshed = repository.with_stars(50)

    expect(repository.full_name).to eq('alice/app')
    expect(repository.stars).to eq(42)
    expect(repository).not_to be_zero_stars
    expect(repository).to include(full_name: 'alice/app', stars: 42)
    expect(repository).to include(:stars)
    expect(repository).to be_key(:stars)
    expect(refreshed.stars).to eq(50)
    expect(repository.stars).to eq(42)
  end

  it 'rejects invalid source records before they cross application boundaries' do
    expect { described_class.new(source_id: nil, login: 'alice') }
      .to raise_error(ArgumentError, 'source_id is required')
    expect { described_class.new(source_id: 1, login: 'team/alice') }
      .to raise_error(ArgumentError, 'Invalid login: "team/alice"')
    expect do
      repository_class.new(
        source_id: 10,
        name: 'app',
        full_name: 'alice/app',
        html_url: 'https://github.com/alice/app',
        fork: false,
        archived: false,
        stars: -1
      )
    end.to raise_error(ArgumentError, 'stars cannot be negative')
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Domain::SourceCandidate do
  it 'exposes hash-compatible candidates, contributors, and repositories' do
    candidate = described_class.new(source_id: 1, login: 'alice')
    contributor = PolishOpenSourceRank::Contexts::Ranking::Domain::SourceContributor.new(
      source_id: 1,
      login: 'alice',
      html_url: 'https://github.com/alice'
    )
    repository = PolishOpenSourceRank::Contexts::Ranking::Domain::SourceRepository.new(
      source_id: 10,
      full_name: 'alice/app',
      stars: 42
    )

    expect(candidate.fetch(:login)).to eq('alice')
    expect(contributor[:html_url]).to eq('https://github.com/alice')
    expect(repository).to include(full_name: 'alice/app', stars: 42)
    expect(repository).to include(:stars)
    expect(repository).to be_key(:stars)
    expect(candidate).to eq(source_id: 1, login: 'alice')
    expect(candidate).not_to eq('alice')
    expect(candidate.fetch(:missing, 'fallback')).to eq('fallback')
  end
end

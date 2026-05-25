# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Languages::Domain::LanguageRepositoryRankingMetric do
  it 'maps repository ranking slugs to supported metric keys' do
    expect(described_class.slugs).to eq(%w[top trending])
    expect(described_class.keys).to eq(%w[repository_stars_count repository_stars_delta])
    expect(described_class.key_for_slug('top')).to eq('repository_stars_count')
    expect(described_class.supported_key?('repository_stars_delta')).to be(true)
    expect(described_class.supported_key?('repository_count')).to be(false)
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Languages::Domain::LanguageRankingMetric do
  it 'owns public language ranking slugs and metric keys' do
    expect(described_class.slugs).to eq(%w[top stars trending])
    expect(described_class.keys).to eq(%w[repository_count repository_stars_count repository_stars_delta])
    expect(described_class.key_for_slug('stars')).to eq('repository_stars_count')
    expect(described_class.supported_key?('repository_count')).to be(true)
    expect(described_class.slugs_pattern).to eq('top|stars|trending')
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::PackageRankingMetric do
  it 'owns public package ranking slugs and storage keys' do
    expect(described_class.slugs).to eq(%w[top downloads dependents])
    expect(described_class.keys).to eq(%w[downloads_30d downloads_total dependents_count])
    expect(described_class.key_for_slug('top')).to eq('downloads_30d')
    expect(described_class.supported_key?(:downloads_total)).to be(true)
    expect(described_class.supported_key?(:unknown)).to be(false)
    expect(described_class.slugs_pattern).to eq('top|downloads|dependents')
  end
end

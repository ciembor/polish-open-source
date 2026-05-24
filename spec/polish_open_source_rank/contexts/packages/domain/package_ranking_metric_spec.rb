# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::PackageRankingMetric do
  it 'owns public package ranking slugs and storage keys' do
    expect(described_class.slugs).to eq(%w[top downloads dependents])
    expect(described_class.keys).to eq(%w[downloads_30d downloads_total dependents_count])
    expect(described_class.key_for_slug('top')).to eq('downloads_30d')
    expect(described_class.supported_key?(:downloads_total)).to be(true)
    expect(described_class.supported_key?(:unknown)).to be(false)
    expect(
      npm_slugs: described_class.slugs(ecosystem: 'npm'),
      crates_keys: described_class.keys(ecosystem: 'crates'),
      packagist_keys: described_class.keys(ecosystem: 'packagist'),
      pypi_keys: described_class.keys(ecosystem: 'pypi')
    ).to eq(
      npm_slugs: %w[top],
      crates_keys: %w[downloads_30d downloads_total],
      packagist_keys: %w[downloads_30d downloads_total],
      pypi_keys: []
    )
    expect(described_class.supported_for_ecosystem?('npm', 'downloads_total')).to be(false)
    expect(described_class.slugs_pattern).to eq('top|downloads|dependents')
  end
end

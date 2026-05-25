# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::PackageRankingMetric do
  it 'owns public package ranking slugs and storage keys' do
    expect(described_class.slugs).to eq(%w[top downloads dependents stars trending])
    expect(described_class.keys).to eq(
      %w[downloads_30d downloads_total dependents_count repository_stars_count repository_stars_delta]
    )
    expect(described_class.key_for_slug('top')).to eq('downloads_30d')
    expect(described_class.supported_key?(:downloads_total)).to be(true)
    expect(described_class.supported_key?(:unknown)).to be(false)
    expect(described_class.supported_for_ecosystem?('npm', 'downloads_total')).to be(false)
    expect(described_class.slugs_pattern).to eq('top|downloads|dependents|stars|trending')
  end

  it 'maps ranking metrics to the ecosystems that can expose them' do
    expect(
      npm_slugs: described_class.slugs(ecosystem: 'npm'),
      crates_keys: described_class.keys(ecosystem: 'crates'),
      packagist_keys: described_class.keys(ecosystem: 'packagist'),
      homebrew_slugs: described_class.slugs(ecosystem: 'homebrew'),
      nuget_keys: described_class.keys(ecosystem: 'nuget'),
      maven_keys: described_class.keys(ecosystem: 'maven'),
      pypi_keys: described_class.keys(ecosystem: 'pypi'),
      terraform_slugs: described_class.slugs(ecosystem: 'terraform'),
      apt_slugs: described_class.slugs(ecosystem: 'apt')
    ).to eq(
      npm_slugs: %w[top stars trending],
      crates_keys: %w[downloads_30d downloads_total repository_stars_count repository_stars_delta],
      packagist_keys: %w[downloads_30d downloads_total repository_stars_count repository_stars_delta],
      homebrew_slugs: %w[top stars trending],
      nuget_keys: %w[downloads_total repository_stars_count repository_stars_delta],
      maven_keys: %w[repository_stars_count repository_stars_delta],
      pypi_keys: %w[repository_stars_count repository_stars_delta],
      terraform_slugs: %w[stars trending],
      apt_slugs: %w[stars trending]
    )
  end
end

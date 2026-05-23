# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackage do
  it 'normalizes package identity and preserves nil metrics through snapshots' do
    package = described_class.new(
      ecosystem: 'npm',
      package_name: '@Scope/Tool',
      registry_url: 'https://www.npmjs.com/package/@Scope/Tool',
      latest_version: '1.2.3'
    )
    snapshot = PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageSnapshot.new(
      ecosystem: 'npm',
      package_name: '@Scope/Tool',
      downloads_total: nil,
      downloads_30d: 100,
      latest_version: '1.2.3'
    )

    expect(package.to_h).to include(normalized_package_name: '@scope/tool', latest_version: '1.2.3')
    expect(snapshot.to_h).to include(
      normalized_package_name: '@scope/tool',
      downloads_total: nil,
      downloads_7d: nil,
      downloads_30d: 100
    )
  end

  it 'rejects unknown package and fetch statuses' do
    expect do
      described_class.new(ecosystem: 'npm', package_name: 'x', registry_url: 'https://example.com', status: 'stale')
    end.to raise_error(ArgumentError, 'Unsupported registry package status: stale')

    expect do
      PolishOpenSourceRank::Contexts::Packages::Domain::RegistryFetchResult.new(status: 'retry')
    end.to raise_error(ArgumentError, 'Unsupported registry fetch status: retry')
  end
end

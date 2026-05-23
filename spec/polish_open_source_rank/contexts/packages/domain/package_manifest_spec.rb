# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::PackageManifest do
  it 'normalizes package names and exposes parser result fields as a hash' do
    manifest = described_class.new(
      ecosystem: 'npm',
      package_name: 'Scope/Package',
      confidence: 'high',
      parse_status: 'parsed'
    )

    expect(manifest.to_h).to include(
      ecosystem: 'npm',
      package_name: 'Scope/Package',
      normalized_package_name: 'scope/package',
      private_package: false,
      confidence: 'high',
      parse_status: 'parsed',
      metadata: {}
    )
  end

  it 'rejects unknown confidence levels and parse statuses' do
    expect do
      described_class.new(ecosystem: 'npm', confidence: 'certain', parse_status: 'parsed')
    end.to raise_error(ArgumentError, 'Unknown confidence level: certain')
    expect do
      described_class.new(ecosystem: 'npm', confidence: 'high', parse_status: 'executed')
    end.to raise_error(ArgumentError, 'Unknown parse status: executed')
  end
end

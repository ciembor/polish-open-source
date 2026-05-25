# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::Ecosystem do
  it 'owns supported package ecosystems' do
    ecosystems = %w[
      npm rubygems crates pypi hex packagist go homebrew nuget maven terraform conan vcpkg swiftpm pub apt rpm nix
    ]
    expect(described_class::SUPPORTED).to eq(ecosystems)
    expect(described_class.snapshot_supported).to eq(ecosystems)
    expect(described_class.supported?('npm')).to be(true)
    expect(described_class.supported?(nil)).to be(true)
    expect(described_class.supported?('unknown')).to be(false)
    expect(described_class.snapshot_supported?('nuget')).to be(true)
    expect(described_class.snapshot_supported_list).to eq(ecosystems.join(', '))
  end
end

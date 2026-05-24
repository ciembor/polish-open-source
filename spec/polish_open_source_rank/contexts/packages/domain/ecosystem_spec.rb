# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::Ecosystem do
  it 'owns supported package ecosystems' do
    expect(described_class::SUPPORTED).to eq(%w[npm rubygems crates pypi hex packagist go homebrew nuget maven])
    expect(described_class.snapshot_supported).to eq(%w[npm rubygems crates pypi hex packagist go homebrew nuget])
    expect(described_class.supported?('npm')).to be(true)
    expect(described_class.supported?(nil)).to be(true)
    expect(described_class.supported?('unknown')).to be(false)
    expect(described_class.snapshot_supported?('nuget')).to be(true)
    expect(described_class.snapshot_supported_list).to eq(
      'npm, rubygems, crates, pypi, hex, packagist, go, homebrew, nuget'
    )
  end
end

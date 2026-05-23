# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::Ecosystem do
  it 'owns supported package ecosystems' do
    expect(described_class::SUPPORTED).to eq(%w[npm rubygems crates pypi hex packagist go nuget maven])
    expect(described_class.supported?('npm')).to be(true)
    expect(described_class.supported?(nil)).to be(true)
    expect(described_class.supported?('unknown')).to be(false)
  end
end

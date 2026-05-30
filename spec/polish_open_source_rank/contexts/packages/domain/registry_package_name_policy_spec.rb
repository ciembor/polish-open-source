# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Domain::RegistryPackageNamePolicy do
  it 'ignores invalid npm workspace paths and keeps scoped package names fetchable' do
    expect(described_class.ignored?(ecosystem: 'npm', normalized_package_name: 'app-init/feature')).to be(true)
    expect(described_class.ignored?(ecosystem: 'npm', normalized_package_name: '@scope/package')).to be(false)
    expect(described_class.error_for(ecosystem: 'npm')).to eq('invalid npm package name')
  end

  it 'ignores placeholder names only for registries that allow those placeholders' do
    expect(described_class.ignored?(ecosystem: 'rubygems', normalized_package_name: 'foo')).to be(true)
    expect(described_class.ignored?(ecosystem: 'pypi', normalized_package_name: 'example')).to be(true)
    expect(described_class.ignored?(ecosystem: 'npm', normalized_package_name: 'foo')).to be(false)
    expect(described_class.error_for(ecosystem: 'rubygems')).to eq('placeholder package name')
  end
end

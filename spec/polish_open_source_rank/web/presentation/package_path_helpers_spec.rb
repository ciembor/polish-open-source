# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PackagePathHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::LogoIconHelpers
      include PolishOpenSourceRank::Web::Presentation::PackagePathHelpers
    end.new
  end

  describe '#package_ecosystem_initial' do
    it 'returns the initial of the ecosystem display name' do
      expect(helper.package_ecosystem_initial('rubygems')).to eq('R')
    end
  end

  describe '#package_ecosystem_icon_exists?' do
    it 'returns true when the ecosystem icon exists' do
      expect(helper.package_ecosystem_icon_exists?('npm')).to be(true)
    end
  end
end

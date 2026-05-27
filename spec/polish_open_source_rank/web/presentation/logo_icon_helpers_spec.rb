# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::LogoIconHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::LogoIconHelpers
    end.new
  end

  describe '#logo_icon_initial' do
    it 'returns the uppercased first character' do
      expect(helper.logo_icon_initial('bitbake')).to eq('B')
    end

    it 'returns a fallback for blank values' do
      expect(helper.logo_icon_initial('')).to eq('?')
    end
  end

  describe '#logo_icon_exists?' do
    it 'returns true when a public icon exists' do
      expect(helper.logo_icon_exists?('/icons/languages/ruby.svg')).to be(true)
    end

    it 'returns false when a public icon is missing' do
      expect(helper.logo_icon_exists?('/icons/languages/definitely_missing.svg')).to be(false)
    end
  end
end

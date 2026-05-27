# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::LanguagePathHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::LogoIconHelpers
      include PolishOpenSourceRank::Web::Presentation::LanguagePathHelpers
    end.new
  end

  describe '#language_initial' do
    it 'returns the uppercased first character' do
      expect(helper.language_initial('bitbake')).to eq('B')
    end
  end
end

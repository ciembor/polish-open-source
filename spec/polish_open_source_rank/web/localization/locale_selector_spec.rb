# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Localization::LocaleSelector do
  subject(:selector) { described_class.new(supported: %w[en pl], default: 'pl') }

  it 'prefers an explicit locale over cookies' do
    locale = selector.select(
      params: { 'lang' => 'pl' },
      cookies: { 'locale' => 'en' }
    )

    expect(locale).to eq('pl')
  end

  it 'falls back through cookie and default locale without using accepted languages' do
    expect(selector.select(params: {}, cookies: { 'locale' => 'pl' })).to eq('pl')
    expect(selector.select(params: {}, cookies: {})).to eq('pl')
    unsupported_locale = selector.select(
      params: { 'lang' => 'de' },
      cookies: { 'locale' => 'de' }
    )
    expect(unsupported_locale).to eq('pl')
  end
end

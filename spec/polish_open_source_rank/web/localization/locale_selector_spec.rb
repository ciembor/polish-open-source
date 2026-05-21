# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Localization::LocaleSelector do
  subject(:selector) { described_class.new(supported: %w[en pl], default: 'pl') }

  it 'prefers an explicit locale over cookies and accepted languages' do
    locale = selector.select(
      params: { 'lang' => 'pl' },
      cookies: { 'locale' => 'en' },
      accept_language: 'en-US,en;q=0.9'
    )

    expect(locale).to eq('pl')
  end

  it 'falls back through cookie, accepted language and default locale' do
    expect(selector.select(params: {}, cookies: { 'locale' => 'pl' }, accept_language: 'en')).to eq('pl')
    expect(selector.select(params: {}, cookies: {}, accept_language: 'pl-PL,pl;q=0.9')).to eq('pl')
    unsupported_locale = selector.select(
      params: { 'lang' => 'de' },
      cookies: { 'locale' => 'de' },
      accept_language: 'de'
    )
    expect(unsupported_locale).to eq('pl')
  end
end

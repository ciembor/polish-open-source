# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::RoutingHelpers do
  subject(:helper_host) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::RoutingHelpers

      def settings
        Struct.new(:default_locale).new('pl')
      end
    end.new
  end

  it 'builds localized public paths and recognizes localizable routes', :aggregate_failures do
    expect(helper_host.send(:localized_public_path, '', locale: 'pl')).to eq('/')
    expect(helper_host.send(:localized_public_path, '/latest', locale: 'pl')).to eq('/latest')
    expect(helper_host.send(:localized_public_path, '/', locale: 'en')).to eq('/en')
    expect(helper_host.send(:localized_public_path, '/latest', locale: 'en')).to eq('/en/latest')
    expect(helper_host.send(:localized_public_path, '/auth/github', locale: 'en')).to eq('/auth/github')

    expect(helper_host.send(:localized_page_path?, '/')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/about')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/users/github/alice')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/repositories/github/alice/app')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/2026-04/locations/krakow')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/auth/github')).to be(false)
  end
end

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
    expect(helper_host.send(:localized_page_path?, '/organizations')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/users/github/alice')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/repositories/github/alice/app')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/2026-04/locations/krakow')).to be(true)
    expect(helper_host.send(:localized_page_path?, '/auth/github')).to be(false)
  end

  it 'builds people and organization paths for the selected scope', :aggregate_failures do
    helper_host.instance_variable_set(:@period_slug, 'latest')
    helper_host.instance_variable_set(:@scope, { slug: 'krakow' })

    expect(helper_host.people_rankings_path).to eq('/latest/locations/krakow')
    expect(helper_host.organization_rankings_path).to eq('/latest/organizations/locations/krakow')
    expect(helper_host.section_scope_path({ slug: 'poland' }, section: 'people')).to eq('/latest')
    expect(helper_host.section_scope_path({ slug: 'poland' }, section: 'organizations')).to eq('/latest/organizations')
    expect(helper_host.section_scope_path({ slug: 'warszawa' }, section: 'organizations')).to(
      eq('/latest/organizations/locations/warszawa')
    )
  end

  it 'builds page-specific schema types' do
    helper_host.instance_variable_set(:@canonical_path, '/about')
    expect(helper_host.send(:structured_data_type)).to eq('AboutPage')

    helper_host.remove_instance_variable(:@canonical_path)
    helper_host.instance_variable_set(:@profile, { login: 'alice', html_url: 'https://github.com/alice' })
    expect(helper_host.send(:structured_data_type)).to eq('ProfilePage')

    helper_host.remove_instance_variable(:@profile)
    helper_host.instance_variable_set(
      :@repository,
      { full_name: 'alice/app', html_url: 'https://github.com/alice/app' }
    )
    expect(helper_host.send(:structured_data_type)).to eq('SoftwareSourceCode')
  end

  it 'returns no collection schema for pages without list content' do
    expect(helper_host.send(:collection_schema)).to be_nil
  end
end

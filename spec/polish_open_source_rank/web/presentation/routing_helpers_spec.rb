# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::RoutingHelpers do
  subject(:helper_host) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::RoutingHelpers

      attr_accessor :current_user, :env, :request

      def initialize
        @env = {}
        @request = Struct.new(:path_info, :query_string).new('/', '')
      end

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

    expect(helper_host.people_rankings_path).to eq('/people/locations/krakow')
    expect(helper_host.organization_rankings_path).to eq('/organizations/locations/krakow')
    expect(helper_host.section_scope_path({ slug: 'poland' }, section: 'people')).to eq('/people')
    expect(helper_host.section_scope_path({ slug: 'poland' }, section: 'organizations')).to eq('/organizations')
    expect(helper_host.section_scope_path({ slug: 'warszawa' }, section: 'organizations')).to(
      eq('/organizations/locations/warszawa')
    )
  end

  it 'adds SEO slugs to profile paths only when the display name differs from the login', :aggregate_failures do
    expect(helper_host.user_profile_path(platform: 'github', login: 'jkowalski', name: 'Jan Kowalski')).to eq(
      '/users/github/jkowalski/jan-kowalski'
    )
    expect(helper_host.user_profile_path(platform: 'github', login: 'alice', name: 'Alice')).to eq(
      '/users/github/alice'
    )
    expect(helper_host.organization_profile_path(platform: 'github', login: 'acme-dev', name: 'Acme Labs')).to eq(
      '/organizations/github/acme-dev/acme-labs'
    )
    expect(helper_host.organization_profile_path(platform: 'github', login: 'polish-org', name: 'Polish Org')).to eq(
      '/organizations/github/polish-org'
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

  it 'marks navigation links active for section pages and subpages', :aggregate_failures do
    helper_host.request.path_info = '/2026-04/locations/krakow/users/active'
    helper_host.env['polish_open_source_rank.unlocalized_path'] = '/2026-04/locations/krakow/users/active'
    expect(helper_host.nav_link_active?(:people)).to be(true)
    expect(helper_host.active_nav_link_class(:people)).to eq('is-active')
    expect(helper_host.nav_link_active?(:organizations)).to be(false)

    helper_host.request.path_info = '/organizations/github/polish-org'
    helper_host.env['polish_open_source_rank.unlocalized_path'] = '/organizations/github/polish-org'
    expect(helper_host.nav_link_active?(:organizations)).to be(true)
    expect(helper_host.nav_link_active?(:people)).to be(false)

    helper_host.current_user = { platform: 'github', login: 'alice' }
    helper_host.request.path_info = '/users/github/alice'
    helper_host.env['polish_open_source_rank.unlocalized_path'] = '/users/github/alice'
    expect(helper_host.nav_link_active?(:profile)).to be(true)
    expect(helper_host.nav_link_active?(:people)).to be(false)

    helper_host.request.path_info = '/en/editions/2025'
    helper_host.env['polish_open_source_rank.unlocalized_path'] = '/editions/2025'
    expect(helper_host.nav_link_active?(:editions)).to be(true)

    helper_host.request.path_info = '/en/about'
    helper_host.env['polish_open_source_rank.unlocalized_path'] = '/about'
    expect(helper_host.nav_link_active?(:about)).to be(true)
    expect(helper_host.nav_link_active?(:missing)).to be(false)
  end
end

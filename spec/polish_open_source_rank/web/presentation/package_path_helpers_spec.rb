# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PackagePathHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::LogoIconHelpers
      include PolishOpenSourceRank::Web::Presentation::ViewHelpers
      include PolishOpenSourceRank::Web::Presentation::ProfilePathHelpers
      include PolishOpenSourceRank::Web::Presentation::PackageOwnerHelpers
      include PolishOpenSourceRank::Web::Presentation::PackagePathHelpers

      def app_path(path)
        "/rank#{path}"
      end

      def current_locale
        'pl'
      end

      def localized_public_path(path, locale:)
        locale == 'pl' ? path : "/#{locale}#{path}"
      end
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

  describe '#package_ranking_grid_class' do
    it 'uses two columns for an even metric count' do
      expect(helper.package_ranking_grid_class(4)).to eq('ranking-grid--compact')
    end

    it 'uses three columns for an odd metric count' do
      expect(helper.package_ranking_grid_class(3)).to eq('ranking-grid--odd-package-metrics')
    end
  end

  describe '#package_repository_link' do
    it 'links to the source repository detected by package scanning' do
      row = repository_row(
        repository_html_url: 'https://github.com/alice/app',
        repository_url: 'https://github.com/registry/metadata'
      )

      expect(helper.package_repository_link(row)).to eq('https://github.com/alice/app')
    end

    it 'does not fall back to registry repository metadata without a linked source repository' do
      row = repository_row(repository_html_url: nil, repository_url: 'https://github.com/registry/metadata')

      expect(helper.package_repository_link(row)).to be_nil
    end

    it 'keeps the local repository profile link available separately' do
      expect(helper.package_repository_profile_link(repository_row)).to eq('/rank/repositories/github/alice/app')

      row = repository_row(repository_full_name: 'polish-org/toolkit', repository_kind: 'organization')

      expect(helper.package_repository_profile_link(row)).to eq(
        '/rank/organization-repositories/github/polish-org/toolkit'
      )
    end

    it 'returns nil when the linked source repository URL is not safe' do
      row = repository_row(repository_html_url: 'javascript:alert(1)')

      expect(helper.package_repository_link(row)).to be_nil
    end
  end

  describe '#package_owner_profile_link' do
    it 'links package owners to the local user profile when the package belongs to a user repository' do
      row = repository_row(repository_owner_login: 'alice', repository_owner_name: 'Alice Example')

      expect(helper.package_owner_profile_link(row)).to eq('/rank/users/github/alice/alice-example')
    end

    it 'links package owners to the local organization profile' do
      row = repository_row(
        repository_kind: 'organization',
        repository_owner_login: 'polish-org',
        repository_owner_name: 'Polish Org'
      )

      expect(helper.package_owner_profile_link(row)).to eq('/rank/organizations/github/polish-org')
    end

    it 'returns nil when the package owner login is missing' do
      expect(helper.package_owner_profile_link(repository_row(repository_owner_login: nil))).to be_nil
    end
  end

  describe '#package_owner_display_name' do
    it 'adds the login to the owner name when both are available' do
      row = repository_row(repository_owner_name: 'Alice Example', repository_owner_login: 'alice')

      expect(helper.package_owner_display_name(row)).to eq('Alice Example (alice)')
    end

    it 'uses the login alone when the owner name is missing or duplicated' do
      expect(helper.package_owner_display_name(repository_row(repository_owner_login: 'alice'))).to eq('alice')
      expect(helper.package_owner_display_name(repository_row(repository_owner_name: 'Alice',
                                                              repository_owner_login: 'alice'))).to eq('alice')
    end
  end

  def repository_row(attributes = {})
    {
      registry_url: nil,
      repository_url: nil,
      repository_platform: 'github',
      repository_full_name: 'alice/app',
      repository_html_url: 'https://github.com/alice/app',
      repository_kind: 'user',
      repository_owner_name: nil,
      repository_owner_login: nil
    }.merge(attributes)
  end
end

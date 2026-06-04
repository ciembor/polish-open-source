# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PackagePathHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::LogoIconHelpers
      include PolishOpenSourceRank::Web::Presentation::ViewHelpers
      include PolishOpenSourceRank::Web::Presentation::ProfilePathHelpers
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
    it 'links to the local repository profile for linked package repositories' do
      row = repository_row(repository_url: 'https://github.com/registry/metadata')

      expect(helper.package_repository_link(row)).to eq('/rank/repositories/github/alice/app')
    end

    it 'does not fall back to registry repository metadata without a linked local repository' do
      row = repository_row(repository_url: 'https://github.com/registry/metadata', repository_full_name: nil)

      expect(helper.package_repository_link(row)).to be_nil
    end

    it 'links organization repositories to their local profile' do
      row = repository_row(repository_url: nil, repository_full_name: 'polish-org/toolkit',
                           repository_kind: 'organization')

      expect(helper.package_repository_link(row)).to eq('/rank/organization-repositories/github/polish-org/toolkit')
    end

    it 'returns nil when the package has neither registry repository metadata nor a linked repository profile' do
      row = repository_row(repository_url: nil, repository_full_name: nil)

      expect(helper.package_repository_link(row)).to be_nil
    end
  end

  def repository_row(attributes)
    {
      registry_url: nil,
      repository_url: nil,
      repository_platform: 'github',
      repository_full_name: 'alice/app',
      repository_kind: 'user'
    }.merge(attributes)
  end
end

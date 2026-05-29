# frozen_string_literal: true

class PublicPageStateFakeViewContext
  attr_reader :session

  def initialize
    @session = { discord_error: 'Sync failed' }
  end

  def t(key, values = {})
    serialized = values.sort_by(&:first).map { |name, value| "#{name}=#{value}" }.join('|')
    return key if serialized.empty?

    "#{key}|#{serialized}"
  end

  def platform_name(platform)
    { 'github' => 'GitHub' }.fetch(platform)
  end

  def user_profile_path(profile)
    "/users/#{profile.fetch(:platform)}/#{profile.fetch(:login)}"
  end

  def show_discord_panel_for(_profile)
    :discord_panel
  end

  def repository_profile_path(repository)
    "/repositories/#{repository.fetch(:platform)}/#{repository.fetch(:full_name)}"
  end

  def organization_profile_path(organization)
    "/organizations/#{organization.fetch(:platform)}/#{organization.fetch(:login)}"
  end

  def organization_repository_profile_path(repository)
    "/organization-repositories/#{repository.fetch(:platform)}/#{repository.fetch(:full_name)}"
  end

  def ranking_title(kind, metric)
    { 'users/top' => 'Users Top' }.fetch("#{kind}/#{metric}")
  end

  def scope_name(scope)
    scope.fetch(:name)
  end

  def ranking_metric_label(kind, metric)
    { 'users/top' => 'Total stars' }.fetch("#{kind}/#{metric}")
  end

  def ranking_path(kind, metric, period_slug:, scope_slug:)
    "/#{period_slug}/locations/#{scope_slug}/#{kind}/#{metric}"
  end

  def editions_path(year = nil)
    year ? "/editions/#{year}" : '/editions'
  end

  def period_base_path(period_slug)
    "/#{period_slug}"
  end

  def city_path(slug, period_slug:)
    "/#{period_slug}/locations/#{slug}"
  end

  def organization_rankings_path(period_slug:, scope_slug: 'poland')
    path = "/#{period_slug}/organizations"
    return path if scope_slug == 'poland'

    "#{path}/locations/#{scope_slug}"
  end

  def period_label(period_start)
    {
      '2026-04-01' => 'April 2026'
    }.fetch(period_start)
  end
end

RSpec.describe PolishOpenSourceRank::Web::Presentation::PublicPageState do
  subject(:page_state) { described_class.new(view_context) }

  let(:view_context) { PublicPageStateFakeViewContext.new }

  describe '#rankings' do
    let(:page) do
      Struct.new(
        :user_rankings,
        :repository_rankings,
        :organization_rankings,
        :organization_repository_rankings
      ).new({ top: [] }, { top: [] }, { top: [] }, { top: [] })
    end

    it 'builds the latest Poland rankings page state' do
      state = page_state.rankings(
        scope: { slug: 'poland', name: 'Poland' },
        period_slug: 'latest',
        page: page
      )

      expect(state).to include(
        user_rankings: { top: [] },
        repository_rankings: { top: [] },
        organization_rankings: { top: [] },
        organization_repository_rankings: { top: [] },
        title: 'rankings.seo.title_latest|period=rankings.seo.current_period|scope=Poland',
        description: 'rankings.seo.description_latest|period=rankings.seo.current_period|scope=Poland',
        canonical_path: '/latest'
      )
    end

    it 'builds city ranking metadata for historical periods' do
      state = page_state.rankings(
        scope: { slug: 'krakow', name: 'Krakow' },
        period_slug: '2026-04',
        page: page
      )

      expect(state).to include(
        title: 'rankings.seo.title_period|period=April 2026|scope=Krakow',
        description: 'rankings.seo.description_period|period=April 2026|scope=Krakow',
        canonical_path: '/2026-04/locations/krakow'
      )
    end

    it 'builds organization ranking metadata with organization canonical paths' do
      state = page_state.rankings(
        scope: { slug: 'krakow', name: 'Krakow' },
        period_slug: 'latest',
        section: 'organizations',
        page: page
      )

      expect(state).to include(
        title: 'rankings.seo.organizations_title_latest|period=rankings.seo.current_period|scope=Krakow',
        description: 'rankings.seo.organizations_description_latest|period=rankings.seo.current_period|scope=Krakow',
        canonical_path: '/latest/organizations/locations/krakow'
      )
    end
  end

  describe '#user_profile' do
    let(:profile) do
      {
        platform: 'github',
        login: 'ciembor',
        name: '',
        repositories: [{ full_name: 'ciembor/app' }]
      }
    end

    it 'builds the signed-in user profile state' do
      state = page_state.user_profile(profile: profile, own_profile: true)

      expect(state).to include(
        repositories: [{ full_name: 'ciembor/app' }],
        title: 'users.seo.title|platform=GitHub|user=ciembor',
        description: 'users.seo.description|platform=GitHub|user=ciembor',
        canonical_path: '/users/github/ciembor',
        discord_panel: :discord_panel,
        discord_error: 'Sync failed',
        show_profile_badges: true
      )
      expect(view_context.session).to be_empty
    end

    it 'does not expose private profile affordances for public viewers' do
      state = page_state.user_profile(profile: profile.merge(name: 'Maciej'), own_profile: false)

      expect(state).to include(
        title: 'users.seo.title|platform=GitHub|user=Maciej',
        description: 'users.seo.description|platform=GitHub|user=Maciej',
        discord_panel: nil,
        discord_error: nil,
        show_profile_badges: false
      )
    end
  end

  describe '#repository_profile' do
    let(:repository) do
      {
        platform: 'github',
        full_name: 'ciembor/polish-open-source-rank'
      }
    end

    it 'builds repository page state and ownership flag' do
      state = page_state.repository_profile(repository: repository, own_repository: true)

      expect(state).to include(
        title: 'repositories.seo.title|platform=GitHub|repository=ciembor/polish-open-source-rank',
        description: 'repositories.seo.description|platform=GitHub|repository=ciembor/polish-open-source-rank',
        canonical_path: '/repositories/github/ciembor/polish-open-source-rank',
        show_repository_badge: true
      )
    end
  end

  describe '#ranking_detail' do
    let(:ranking) { [{ login: 'ciembor', rank: 1 }] }

    it 'builds ranking detail metadata and preserves the ranking payload' do
      state = page_state.ranking_detail(
        scope: { slug: 'krakow', name: 'Krakow' },
        period_slug: '2026-04',
        kind: 'users',
        metric: 'top',
        ranking: ranking
      )

      expect(state).to include(
        ranking: ranking,
        title: 'rankings.seo.detail_title|period=April 2026|ranking=Users Top|scope=Krakow',
        description:
          'rankings.seo.detail_description|metric=Total stars|period=April 2026|ranking=Users Top|scope=Krakow',
        canonical_path: '/2026-04/locations/krakow/users/top'
      )
    end
  end
end

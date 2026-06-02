# frozen_string_literal: true

class DiscoveryStore
  attr_reader :candidates, :organization_candidates

  def initialize
    @candidates = []
    @organization_candidates = []
  end

  def record_candidate(period, **attributes)
    candidates << attributes.merge(period: period)
  end

  def record_organization_candidate(period, **attributes)
    organization_candidates << attributes.merge(period: period)
  end
end

class DiscoveryCatalog
  attr_reader :search_terms

  def initialize(search_terms)
    @search_terms = search_terms
  end
end

class DiscoverySource
  attr_reader :organization_terms, :platform, :user_terms

  def initialize(platform:, users:, organizations: {}, supports_organizations: false)
    @platform = platform
    @users = users
    @organizations = organizations
    @supports_organizations = supports_organizations
    @user_terms = []
    @organization_terms = []
  end

  def supports_organizations?
    @supports_organizations
  end

  def search_users_by_location(term)
    user_terms << term
    @users.fetch(term, [])
  end

  def search_organizations_by_location(term)
    organization_terms << term
    @organizations.fetch(term, [])
  end
end

class DiscoveryMutex
  attr_reader :synchronize_calls

  def initialize
    @synchronize_calls = 0
  end

  def synchronize
    @synchronize_calls += 1
    yield
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Application::MonthlyCandidateDiscovery do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:store) { DiscoveryStore.new }
  let(:catalog) { DiscoveryCatalog.new(%w[Poland Warszawa]) }
  let(:logger) { StringIO.new }
  let(:mutex) { DiscoveryMutex.new }

  it 'discovers user candidates through catalog search terms' do
    source = DiscoverySource.new(
      platform: 'github',
      users: {
        'Poland' => [{ source_id: 1, login: 'alice' }],
        'Warszawa' => [{ source_id: 2, login: 'bob' }]
      }
    )

    discovery.discover_users(period, source)

    expect(source.user_terms).to eq(%w[Poland Warszawa])
    expect(store.candidates).to eq(
      [
        { period: period, platform: 'github', source_id: 1, login: 'alice', source_query: 'Poland' },
        { period: period, platform: 'github', source_id: 2, login: 'bob', source_query: 'Warszawa' }
      ]
    )
    expect(logger.string).to include('[github] discovering users for location "Poland"')
    expect(logger.string).to include('[github] candidate discovery finished')
    expect(mutex.synchronize_calls).to eq(2)
  end

  it 'discovers organization candidates when the source supports organizations' do
    source = DiscoverySource.new(
      platform: 'github',
      users: {},
      organizations: { 'Poland' => [{ source_id: 9, login: 'polish-org' }] },
      supports_organizations: true
    )

    discovery.discover_organizations(period, source)

    expect(source.organization_terms).to eq(%w[Poland Warszawa])
    expect(store.organization_candidates).to eq(
      [
        { period: period, platform: 'github', source_id: 9, login: 'polish-org', source_query: 'Poland' }
      ]
    )
    expect(logger.string).to include('[github] discovering organizations for location "Poland"')
    expect(logger.string).to include('[github] organization discovery finished')
  end

  it 'leaves unsupported organization sources untouched' do
    source = DiscoverySource.new(platform: 'gitlab', users: {}, organizations: {}, supports_organizations: false)

    discovery.discover_organizations(period, source)

    expect(source.organization_terms).to be_empty
    expect(store.organization_candidates).to be_empty
    expect(logger.string).to be_empty
  end

  def discovery
    described_class.new(store: store, catalog: catalog, logger: logger, store_mutex: mutex)
  end
end

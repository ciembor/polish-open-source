# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRankingReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'package_rankings.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end
  let(:read_model) { described_class.new(database) }
  let(:period) { '2026-04-01' }

  it 'lists ecosystems with package snapshots for a period' do
    seed_package(ecosystem: 'npm', name: 'alpha', downloads_30d: 10)
    seed_package(ecosystem: 'rubygems', name: 'tool', downloads_30d: 20)
    seed_package(ecosystem: 'pypi', name: 'old', period_start: '2026-03-01', downloads_30d: 30)

    expect(read_model.ecosystems(period_start: period)).to eq(%w[npm rubygems])
  end

  it 'ranks packages per ecosystem and metric with deterministic tie breakers' do
    seed_package(ecosystem: 'npm', name: 'zeta', downloads_30d: 50, downloads_total: 100, dependents_count: 5)
    seed_package(ecosystem: 'npm', name: 'alpha', downloads_30d: 50, downloads_total: 80, dependents_count: 7)
    seed_package(ecosystem: 'npm', name: 'nil-downloads', downloads_30d: nil, downloads_total: 1)
    seed_package(ecosystem: 'rubygems', name: 'ruby-zeta', downloads_total: 100, dependents_count: 5)
    seed_package(ecosystem: 'rubygems', name: 'ruby-alpha', downloads_total: 80, dependents_count: 7)
    seed_package(ecosystem: 'crates', name: 'crate', downloads_30d: 10)
    seed_package(ecosystem: 'packagist', name: 'vendor/zeta', downloads_30d: 50, downloads_total: 400)
    seed_package(ecosystem: 'packagist', name: 'vendor/alpha', downloads_30d: 60, downloads_total: 300)
    seed_package(ecosystem: 'packagist', name: 'vendor/nil-downloads', downloads_30d: nil, downloads_total: 1)

    expect(package_names('npm', :downloads_30d)).to eq(%w[alpha zeta])
    expect(package_names('rubygems', :downloads_total)).to eq(%w[ruby-zeta ruby-alpha])
    expect(package_names('rubygems', :dependents_count)).to eq(%w[ruby-alpha ruby-zeta])
    expect(package_names('packagist', :downloads_30d)).to eq(%w[vendor/alpha vendor/zeta])
    expect(package_names('packagist', :downloads_total)).to eq(%w[vendor/zeta vendor/alpha vendor/nil-downloads])
  end

  it 'returns ranking metrics supported by the ecosystem' do
    seed_package(ecosystem: 'packagist', name: 'vendor/alpha', downloads_30d: 50, downloads_total: 100)

    rankings = read_model.rankings(ecosystem: 'packagist', period_start: period)

    expect(rankings.keys).to eq(%i[downloads_30d downloads_total])
    expect(rankings.fetch(:downloads_30d).first).to include(package_name: 'vendor/alpha')
    expect(rankings.fetch(:downloads_total).first).to include(package_name: 'vendor/alpha')
  end

  it 'includes repository ownership from user and organization repositories' do
    seed_package(ecosystem: 'npm', name: 'shared', downloads_30d: 100)
    link_repository(name: 'shared', scan_id: 10, full_name: 'alice/app', repository_kind: 'user')
    link_repository(name: 'shared', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization')

    row = read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_30d').first

    expect(row).to include(
      package_name: 'shared',
      registry_url: 'https://www.npmjs.com/package/shared',
      latest_version: '1.0.0',
      license: 'MIT',
      linked_repository_count: 2,
      repository_full_name: 'alice/app',
      repository_owner_login: 'alice'
    )
  end

  it 'returns package profiles with linked repositories' do
    seed_package(ecosystem: 'npm', name: 'shared', downloads_30d: 100)
    link_repository(name: 'shared', scan_id: 10, full_name: 'alice/app', repository_kind: 'user')
    link_repository(name: 'shared', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization')

    profile = read_model.package_profile(ecosystem: 'npm', package_name: 'SHARED', period_start: period)

    expect(profile).to include(
      ecosystem: 'npm',
      package_name: 'shared',
      downloads_30d: 100,
      repositories: [
        {
          repository_full_name: 'org/tool',
          repository_kind: 'organization',
          repository_platform: 'github',
          repository_owner_login: 'org'
        },
        {
          repository_full_name: 'alice/app',
          repository_kind: 'user',
          repository_platform: 'github',
          repository_owner_login: 'alice'
        }
      ]
    )
  end

  it 'bounds limits and rejects unsupported metrics' do
    seed_package(ecosystem: 'npm', name: 'alpha', downloads_30d: 10)

    expect(read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_30d',
                                      limit: 0).length).to eq(1)
    expect do
      read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'stars')
    end.to raise_error(ArgumentError, 'Unsupported package ranking metric: stars')
    expect do
      read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_total')
    end.to raise_error(ArgumentError, 'Unsupported package ranking metric for npm: downloads_total')
  end

  it 'does not expose non-country package scopes' do
    seed_package(ecosystem: 'npm', name: 'alpha', downloads_30d: 10)

    expect(read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_30d',
                                      scope: 'krakow')).to be_empty
  end

  def package_names(ecosystem, metric)
    read_model.ranked_packages(ecosystem: ecosystem, period_start: period, metric: metric).map do |package|
      package.fetch(:package_name)
    end
  end

  def seed_package(attributes)
    name = attributes.fetch(:name)
    ecosystem = attributes.fetch(:ecosystem)
    database.execute(
      <<~SQL,
        INSERT INTO registry_packages(
          ecosystem, package_name, normalized_package_name, registry_url, repository_url, homepage_url,
          license, latest_version, status, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'active', ?)
      SQL
      [
        ecosystem, name, name.downcase, registry_url(ecosystem, name), "https://github.com/#{name}",
        "https://example.com/#{name}", 'MIT', '1.0.0', '2026-05-23T12:00:00Z'
      ]
    )
    seed_snapshot(attributes)
  end

  def seed_snapshot(attributes)
    database.execute(
      <<~SQL,
        INSERT INTO registry_package_snapshots(
          ecosystem, normalized_package_name, period_start, downloads_total, downloads_30d, downloads_7d,
          dependents_count, dependent_repositories_count, latest_version, latest_release_at, observed_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        attributes.fetch(:ecosystem), attributes.fetch(:name).downcase, attributes.fetch(:period_start, period),
        attributes[:downloads_total], attributes[:downloads_30d], attributes[:downloads_7d],
        attributes[:dependents_count], attributes[:dependent_repositories_count], '1.0.0',
        '2026-05-01T00:00:00Z', '2026-05-23T12:00:00Z'
      ]
    )
  end

  def link_repository(name:, scan_id:, full_name:, repository_kind:)
    seed_scan(scan_id: scan_id, full_name: full_name, repository_kind: repository_kind)
    manifest_id = seed_manifest(scan_id: scan_id, name: name)
    database.execute(
      <<~SQL,
        INSERT INTO registry_package_links(
          manifest_id, ecosystem, normalized_package_name, match_confidence, matched, checked_at
        )
        VALUES (?, 'npm', ?, 'high', 1, ?)
      SQL
      [manifest_id, name.downcase, '2026-05-23T12:00:00Z']
    )
  end

  def seed_scan(scan_id:, full_name:, repository_kind:)
    database.execute(
      <<~SQL,
        INSERT INTO package_repository_scans(
          id, period_start, repository_kind, platform, repository_source_id, full_name, status, updated_at
        )
        VALUES (?, ?, ?, 'github', ?, ?, 'scanned', ?)
      SQL
      [scan_id, period, repository_kind, scan_id, full_name, '2026-05-23T12:00:00Z']
    )
  end

  def seed_manifest(scan_id:, name:)
    database.dataset(:package_manifests).insert(
      repository_scan_id: scan_id,
      ecosystem: 'npm',
      path: 'package.json',
      package_name: name,
      normalized_package_name: name.downcase,
      confidence: 'high',
      parse_status: 'parsed',
      parser_version: 'test',
      parsed_at: '2026-05-23T12:00:00Z'
    )
  end

  def registry_url(ecosystem, name)
    case ecosystem
    when 'npm' then "https://www.npmjs.com/package/#{name}"
    when 'rubygems' then "https://rubygems.org/gems/#{name}"
    when 'packagist' then "https://packagist.org/packages/#{name}"
    else "https://example.com/#{ecosystem}/#{name}"
    end
  end
end

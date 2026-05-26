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

  it 'returns ecosystem cards ordered by linked repository count' do
    seed_package(ecosystem: 'npm', name: 'alpha', downloads_30d: 10)
    seed_package(ecosystem: 'npm', name: 'beta', downloads_30d: 20)
    seed_package(ecosystem: 'rubygems', name: 'tool', downloads_30d: 30)
    link_repository(name: 'alpha', scan_id: 10, full_name: 'alice/app', repository_kind: 'user',
                    stats: { stars: 20, delta: 3 })
    link_repository(name: 'beta', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization',
                    stats: { stars: 30, delta: 1 })
    link_repository(name: 'tool', scan_id: 30, full_name: 'ruby/gem', repository_kind: 'organization',
                    ecosystem: 'rubygems', stats: { stars: 100, delta: 5 })

    expect(read_model.ecosystem_cards(period_start: period)).to eq(
      [
        {
          ecosystem: 'npm',
          package_count: 2,
          repository_count: 2,
          repository_stars_count: 50
        },
        {
          ecosystem: 'rubygems',
          package_count: 1,
          repository_count: 1,
          repository_stars_count: 100
        }
      ]
    )
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
    seed_package(ecosystem: 'homebrew', name: 'brew-zeta', downloads_30d: 70)
    seed_package(ecosystem: 'homebrew', name: 'brew-alpha', downloads_30d: 70)
    seed_package(ecosystem: 'nuget', name: 'NuGet.Zeta', downloads_total: 500)
    seed_package(ecosystem: 'nuget', name: 'NuGet.Alpha', downloads_total: 500)
    seed_package(ecosystem: 'maven', name: 'pl.example:polish-tool')

    expect(package_names('npm', :downloads_30d)).to eq(%w[alpha zeta])
    expect(package_names('rubygems', :downloads_total)).to eq(%w[ruby-zeta ruby-alpha])
    expect(package_names('rubygems', :dependents_count)).to eq(%w[ruby-alpha ruby-zeta])
    expect(package_names('packagist', :downloads_30d)).to eq(%w[vendor/alpha vendor/zeta])
    expect(package_names('packagist', :downloads_total)).to eq(%w[vendor/zeta vendor/alpha vendor/nil-downloads])
    expect(package_names('homebrew', :downloads_30d)).to eq(%w[brew-alpha brew-zeta])
    expect(package_names('nuget', :downloads_total)).to eq(%w[NuGet.Alpha NuGet.Zeta])
    expect(read_model.rankings(ecosystem: 'maven', period_start: period)).to eq(
      repository_stars_count: [],
      repository_stars_delta: []
    )
  end

  it 'returns ranking metrics supported by the ecosystem' do
    seed_package(ecosystem: 'packagist', name: 'vendor/alpha', downloads_30d: 50, downloads_total: 100)
    seed_package(ecosystem: 'homebrew', name: 'polish-tool', downloads_30d: 25)
    seed_package(ecosystem: 'nuget', name: 'Polish.Tool', downloads_total: 1_000)

    rankings = read_model.rankings(ecosystem: 'packagist', period_start: period)
    homebrew_rankings = read_model.rankings(ecosystem: 'homebrew', period_start: period)
    nuget_rankings = read_model.rankings(ecosystem: 'nuget', period_start: period)

    expect(rankings.keys).to eq(%i[downloads_30d downloads_total repository_stars_count repository_stars_delta])
    expect(rankings.fetch(:downloads_30d).first).to include(package_name: 'vendor/alpha')
    expect(rankings.fetch(:downloads_total).first).to include(package_name: 'vendor/alpha')
    expect(homebrew_rankings.keys).to eq(%i[downloads_30d repository_stars_count repository_stars_delta])
    expect(homebrew_rankings.fetch(:downloads_30d).first).to include(package_name: 'polish-tool')
    expect(nuget_rankings.keys).to eq(%i[downloads_total repository_stars_count repository_stars_delta])
    expect(nuget_rankings.fetch(:downloads_total).first).to include(package_name: 'Polish.Tool')
  end

  it 'includes repository ownership from user and organization repositories' do
    seed_package(ecosystem: 'npm', name: 'shared', downloads_30d: 100)
    link_repository(name: 'shared', scan_id: 10, full_name: 'alice/app', repository_kind: 'user',
                    stats: { stars: 20, delta: 3 })
    link_repository(name: 'shared', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization',
                    stats: { stars: 30, delta: 1 })
    link_unmatched_repository(name: 'shared', scan_id: 30, full_name: 'other/dependency',
                              repository_kind: 'organization', stats: { stars: 500, delta: 50 })

    row = read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_30d').first

    expect(row).to include(
      package_name: 'shared',
      registry_url: 'https://www.npmjs.com/package/shared',
      latest_version: '1.0.0',
      license: 'MIT',
      linked_repository_count: 2,
      repository_full_name: 'alice/app',
      repository_owner_login: 'alice',
      repository_stars_count: 30,
      repository_stars_delta: 3
    )
  end

  it 'filters ecosystems and package rankings by repository ownership kind' do
    seed_package(ecosystem: 'npm', name: 'user-tool', downloads_30d: 100)
    seed_package(ecosystem: 'npm', name: 'org-tool', downloads_30d: 200)
    seed_package(ecosystem: 'rubygems', name: 'ruby-tool', downloads_30d: 300)
    link_repository(name: 'user-tool', scan_id: 10, full_name: 'alice/app', repository_kind: 'user',
                    stats: { stars: 20, delta: 3 })
    link_repository(name: 'org-tool', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization',
                    stats: { stars: 30, delta: 1 })

    user_rankings = read_model.rankings(
      ecosystem: 'npm',
      period_start: period,
      repository_kind: 'user'
    )
    organization_rankings = read_model.rankings(
      ecosystem: 'npm',
      period_start: period,
      repository_kind: 'organization'
    )

    expect(read_model.ecosystems(period_start: period, repository_kind: 'user')).to eq(['npm'])
    expect(user_rankings.fetch(:downloads_30d).map { |row| row.fetch(:package_name) }).to eq(['user-tool'])
    expect(organization_rankings.fetch(:downloads_30d).map { |row| row.fetch(:package_name) }).to eq(['org-tool'])
  end

  it 'does not expose inactive packages even when old snapshots remain' do
    seed_package(ecosystem: 'rubygems', name: 'foo', downloads_30d: 100, status: 'not_found')

    expect(read_model.ecosystems(period_start: period)).to be_empty
    expect(read_model.ranked_packages(ecosystem: 'rubygems', period_start: period,
                                      metric: 'downloads_total')).to be_empty
  end

  it 'ranks packages by linked repository stars and monthly star trend' do
    seed_package(ecosystem: 'maven', name: 'pl.example:steady')
    seed_package(ecosystem: 'maven', name: 'pl.example:trending')
    link_repository(
      ecosystem: 'maven',
      name: 'pl.example:steady',
      scan_id: 30,
      full_name: 'alice/steady',
      repository_kind: 'user',
      stats: { stars: 100, delta: 0 }
    )
    link_repository(
      ecosystem: 'maven',
      name: 'pl.example:trending',
      scan_id: 40,
      full_name: 'org/trending',
      repository_kind: 'organization',
      stats: { stars: 20, delta: 5 }
    )

    expect(package_names('maven', :repository_stars_count)).to eq(%w[pl.example:steady pl.example:trending])
    expect(package_names('maven', :repository_stars_delta)).to eq(%w[pl.example:trending])
  end

  it 'returns package profiles with linked repositories' do
    seed_package(ecosystem: 'npm', name: 'shared', downloads_30d: 100)
    link_repository(name: 'shared', scan_id: 10, full_name: 'alice/app', repository_kind: 'user',
                    stats: { stars: 20, delta: 3 })
    link_repository(name: 'shared', scan_id: 20, full_name: 'org/tool', repository_kind: 'organization',
                    stats: { stars: 30, delta: 1 })

    profile = read_model.package_profile(ecosystem: 'npm', package_name: 'SHARED', period_start: period)

    expect(profile).to include(
      ecosystem: 'npm',
      package_name: 'shared',
      downloads_30d: 100,
      repository_stars_count: 30,
      repository_stars_delta: 3,
      repositories: shared_package_repositories
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
    expect do
      read_model.ranked_packages(ecosystem: 'npm', period_start: period, metric: 'downloads_30d',
                                 repository_kind: 'team')
    end.to raise_error(ArgumentError, 'Unsupported package repository kind: team')
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

  def shared_package_repositories
    [
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
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        ecosystem, name, name.downcase, registry_url(ecosystem, name), "https://github.com/#{name}",
        "https://example.com/#{name}", 'MIT', '1.0.0', attributes.fetch(:status, 'active'),
        '2026-05-23T12:00:00Z'
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

  def link_repository(name:, scan_id:, full_name:, repository_kind:, ecosystem: 'npm', stats: nil)
    seed_scan(scan_id: scan_id, full_name: full_name, repository_kind: repository_kind)
    seed_repository_stats(scan_id: scan_id, full_name: full_name, repository_kind: repository_kind, stats: stats)
    manifest_id = seed_manifest(scan_id: scan_id, name: name, ecosystem: ecosystem)
    database.execute(
      <<~SQL,
        INSERT INTO registry_package_links(
          manifest_id, ecosystem, normalized_package_name, match_confidence, matched, checked_at
        )
        VALUES (?, ?, ?, 'high', 1, ?)
      SQL
      [manifest_id, ecosystem, name.downcase, '2026-05-23T12:00:00Z']
    )
    manifest_id
  end

  def link_unmatched_repository(name:, scan_id:, full_name:, repository_kind:, ecosystem: 'npm', stats: nil)
    manifest_id = link_repository(name: name, scan_id: scan_id, full_name: full_name, repository_kind: repository_kind,
                                  ecosystem: ecosystem, stats: stats)
    database.dataset(:registry_package_links)
            .where(manifest_id: manifest_id, ecosystem: ecosystem, normalized_package_name: name.downcase)
            .update(matched: 0)
  end

  def seed_repository_stats(scan_id:, full_name:, repository_kind:, stats:)
    return unless stats

    seed_ranked_repository(scan_id: scan_id, full_name: full_name, repository_kind: repository_kind)
    database.dataset(repository_stats_table(repository_kind)).insert(
      period_start: period,
      platform: 'github',
      repository_github_id: scan_id,
      **repository_owner_columns(repository_kind, scan_id, full_name),
      stargazers_count: stats.fetch(:stars),
      monthly_stars_delta: stats.fetch(:delta),
      updated_at: '2026-05-23T12:00:00Z'
    )
  end

  def repository_stats_table(repository_kind)
    repository_kind == 'organization' ? :organization_repository_monthly_stats : :repository_monthly_stats
  end

  def repository_owner_columns(repository_kind, scan_id, full_name)
    if repository_kind == 'organization'
      return {
        organization_github_id: scan_id + 1000,
        organization_login: full_name.split('/').first,
        organization_city: 'Warszawa',
        organization_country: 'Poland'
      }
    end

    {
      owner_github_id: scan_id + 1000,
      owner_login: full_name.split('/').first,
      owner_city: 'Warszawa',
      owner_country: 'Poland'
    }
  end

  def seed_ranked_repository(scan_id:, full_name:, repository_kind:)
    owner_login = full_name.split('/').first
    if repository_kind == 'organization'
      database.dataset(:organizations).insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' })
              .insert(
                platform: 'github',
                github_id: scan_id + 1000,
                login: owner_login,
                html_url: "https://github.com/#{owner_login}",
                updated_at: '2026-05-23T12:00:00Z'
              )
      database.dataset(:organization_repositories)
              .insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' })
              .insert(repository_attributes(scan_id, full_name).merge(
                        organization_github_id: scan_id + 1000,
                        organization_login: owner_login
                      ))
    else
      database.dataset(:users).insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' })
              .insert(
                platform: 'github',
                github_id: scan_id + 1000,
                login: owner_login,
                html_url: "https://github.com/#{owner_login}",
                updated_at: '2026-05-23T12:00:00Z'
              )
      database.dataset(:repositories)
              .insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' })
              .insert(repository_attributes(scan_id, full_name).merge(
                        owner_github_id: scan_id + 1000,
                        owner_login: owner_login
                      ))
    end
  end

  def repository_attributes(scan_id, full_name)
    {
      platform: 'github',
      github_id: scan_id,
      name: full_name.split('/').last,
      full_name: full_name,
      html_url: "https://github.com/#{full_name}",
      fork: 0,
      archived: 0,
      updated_at: '2026-05-23T12:00:00Z'
    }
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

  def seed_manifest(scan_id:, name:, ecosystem: 'npm')
    database.dataset(:package_manifests).insert(
      repository_scan_id: scan_id,
      ecosystem: ecosystem,
      path: ecosystem == 'npm' ? 'package.json' : 'manifest',
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
    when 'homebrew' then "https://formulae.brew.sh/formula/#{name}"
    when 'nuget' then "https://www.nuget.org/packages/#{name}"
    when 'maven' then "https://central.sonatype.com/artifact/#{name.tr(':', '/')}"
    else "https://example.com/#{ecosystem}/#{name}"
    end
  end
end

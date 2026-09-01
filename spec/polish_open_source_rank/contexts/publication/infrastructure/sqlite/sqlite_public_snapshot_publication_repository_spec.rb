# frozen_string_literal: true

RSpec.describe 'SQLitePublicSnapshotPublicationRepository' do
  let(:repository_class) do
    PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLitePublicSnapshotPublicationRepository
  end
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:backup_root) { Dir.mktmpdir }
  let(:clock) { -> { Time.utc(2026, 6, 1, 12, 0, 0) } }
  let(:repository) { build_repository }

  it 'promotes a verified snapshot atomically and creates a database backup' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')

    repository.publish('2026-05-01')

    expect(publication('2026-04-01')).to include(status: 'superseded')
    expect(publication('2026-05-01')).to include(
      status: 'published',
      previous_period_start: '2026-04-01',
      published_at: '2026-06-01T12:00:00Z'
    )
    expect(File.exist?(publication('2026-05-01').fetch(:backup_path))).to be(true)
  end

  it 'materializes badges before exposing the newly published period' do
    seed_publishable_month('2026-05-01')

    repository.publish('2026-05-01')

    expect(published_badge('user', 1)).to include(label: 'Polish Open Source', rank: 1)
    expect(published_badge('organization', 2)).to include(label: 'Polish Open Source Org', rank: 1)
    expect(published_badge('repository', 10)).to include(label: 'Polish .rb Repo', rank: 2)
    expect(published_badge('repository', 11)).to include(label: 'Polish Repo', rank: 2)
    expect(published_badge('organization_repository', 20)).to include(label: 'Polish .rb Repo', rank: 1)
    expect(published_badge('organization_repository', 21)).to include(label: 'Polish Repo', rank: 2)
  end

  it 'refreshes the configured public database after publishing the snapshot' do
    public_database_path = File.join(Dir.mktmpdir, 'public.sqlite3')
    repository = build_repository(public_database_path: public_database_path)
    seed_publishable_month('2026-05-01')

    repository.publish('2026-05-01')

    public_database = open_public_database(public_database_path)
    expect(public_database.fetch_value('PRAGMA integrity_check')).to eq('ok')
    expect(public_database.fetch_value('PRAGMA query_only')).to eq(1)
    expect(public_database.fetch_value(published_period_sql)).to eq('2026-05-01')
    expect(public_database.fetch_all(published_badge_sql, ['2026-05-01', 'user', 1]).first).to include(
      label: 'Polish Open Source',
      rank: 1
    )
  ensure
    public_database&.close
  end

  it 'refreshes the configured public database without changing publication state' do
    public_database_path = File.join(Dir.mktmpdir, 'public.sqlite3')
    repository = build_repository(public_database_path: public_database_path)
    seed_publishable_month('2026-05-01')

    path = repository.refresh_public_database_snapshot

    expect(path).to eq(public_database_path)
    public_database = open_public_database(public_database_path)
    expect(public_database.fetch_value('PRAGMA integrity_check')).to eq('ok')
    expect(public_database.fetch_value(published_period_sql)).to be_nil
  ensure
    public_database&.close
  end

  it 'purges public cache after publishing the snapshot' do
    seed_publishable_month('2026-05-01')
    public_cache_purger = public_cache_purger_spy
    repository = build_repository(public_cache_purger: public_cache_purger)

    repository.publish('2026-05-01')

    expect(public_cache_purger).to have_received(:purge_public_cache).once
  end

  it 'keeps the current public period when badge materialization fails' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')
    public_cache_purger = public_cache_purger_spy
    failing_repository = build_repository(
      badge_materializer: failing_badge_materializer,
      public_cache_purger: public_cache_purger
    )

    expect { failing_repository.publish('2026-05-01') }.to raise_error('badge materialization failed')

    expect(publication('2026-04-01')).to include(status: 'published')
    expect(publication('2026-05-01')).to include(status: 'verified')
    expect(published_badge('repository', 10, period_start: '2026-05-01')).to be_nil
    expect(public_cache_purger).not_to have_received(:purge_public_cache)
  end

  it 'rejects incomplete snapshots and keeps the failure visible' do
    seed_monthly_run('2026-05-01', status: 'running')

    expect { repository.verify('2026-05-01') }.to raise_error(
      repository_class::VerificationFailed,
      /monthly rankings are not finished/
    )
    expect(publication('2026-05-01')).to include(status: 'staged', error: include('monthly rankings'))
  end

  it 'uses the current UTC time by default' do
    allow(Time).to receive(:now).and_return(Time.utc(2026, 6, 2, 9, 30, 0))

    repository_class.new(database).stage('2026-05-01')

    expect(publication('2026-05-01')).to include(staged_at: '2026-06-02T09:30:00Z')
  end

  it 'rejects snapshots while package crawl data is still running' do
    seed_publishable_month('2026-05-01')
    seed_package_run('2026-05-01', ecosystem: 'rubygems', status: 'running')

    expect { repository.verify('2026-05-01') }.to raise_error(
      repository_class::VerificationFailed,
      /package crawls are not finished/
    )
  end

  it 'rolls back to the previous published snapshot without deleting data' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')
    repository.publish('2026-05-01')

    expect(repository.rollback).to eq('2026-04-01')

    expect(publication('2026-05-01')).to include(status: 'rolled_back')
    expect(publication('2026-04-01')).to include(status: 'published')
  end

  it 'purges public cache after rolling back the snapshot' do
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    public_cache_purger = public_cache_purger_spy
    repository = build_repository(public_cache_purger: public_cache_purger)
    repository.publish('2026-04-01')
    repository.publish('2026-05-01')
    public_cache_purger = public_cache_purger_spy
    rollback_repository = build_repository(public_cache_purger: public_cache_purger)

    rollback_repository.rollback

    expect(public_cache_purger).to have_received(:purge_public_cache).once
  end

  it 'refreshes the configured public database after rolling back the snapshot' do
    public_database_path = File.join(Dir.mktmpdir, 'public.sqlite3')
    repository = build_repository(public_database_path: public_database_path)
    seed_publishable_month('2026-04-01')
    seed_publishable_month('2026-05-01')
    repository.publish('2026-04-01')
    repository.publish('2026-05-01')

    repository.rollback

    public_database = open_public_database(public_database_path)
    expect(public_database.fetch_value(published_period_sql)).to eq('2026-04-01')
  ensure
    public_database&.close
  end

  def publication(period_start)
    database.fetch_all(
      'SELECT * FROM public_snapshot_publications WHERE period_start = ?',
      [period_start]
    ).first
  end

  def public_cache_purger_spy
    public_cache_purger_class = Class.new { def purge_public_cache; end }
    instance_spy(public_cache_purger_class, purge_public_cache: true)
  end

  def build_repository(
    badge_materializer: nil,
    public_cache_purger: nil,
    public_database_path: nil
  )
    repository_options = {
      clock: clock,
      publication_effects: build_publication_effects(
        public_cache_purger: public_cache_purger,
        public_database_path: public_database_path
      )
    }
    repository_options[:badge_materializer] = badge_materializer if badge_materializer
    repository_class.new(database, **repository_options)
  end

  def build_publication_effects(public_cache_purger: nil, public_database_path: nil)
    effects_class = PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::
                    SQLitePublicSnapshotPublicationEffects
    effects_class.new(
      database,
      backup_root: backup_root,
      public_cache_purger: public_cache_purger,
      public_database_path: public_database_path
    )
  end

  def published_badge(kind, subject_id, period_start: '2026-05-01')
    database.fetch_all(published_badge_sql, [period_start, kind, subject_id]).first
  end

  def published_badge_sql
    <<~SQL
      SELECT label, status, rank
      FROM published_badges
      WHERE period_start = ? AND badge_kind = ? AND platform = 'github' AND subject_github_id = ?
    SQL
  end

  def published_period_sql
    "SELECT period_start FROM public_snapshot_publications WHERE status = 'published'"
  end

  def open_public_database(path)
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path, readonly: true)
  end

  def seed_publishable_month(period_start)
    seed_monthly_run(period_start)
    seed_user
    seed_organization
    seed_user_stats(period_start)
    seed_repository_stats(period_start)
    seed_organization_stats(period_start)
    seed_organization_repository_stats(period_start)
    seed_package_run(period_start)
  end

  def seed_monthly_run(period_start, status: 'finished')
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      [
        period_start, Date.parse(period_start).next_month.to_s, status,
        '2026-06-01T10:00:00Z', '2026-06-01T11:00:00Z'
      ]
    )
  end

  def seed_user
    database.execute(
      'INSERT OR IGNORE INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-06-01T00:00:00Z']
    )
  end

  def seed_organization
    database.execute(
      'INSERT OR IGNORE INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 2, 'org', 'https://github.com/org', '2026-06-01T00:00:00Z']
    )
  end

  def seed_user_stats(period_start)
    database.execute(<<~SQL, [period_start])
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
      )
      VALUES (?, 'github', 1, 'alice', 'Kraków', 'Poland', 1, 10, 1, 1, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_repository_stats(period_start)
    seed_repository_record(id: 10, name: 'app', full_name: 'alice/app', language: 'Ruby')
    seed_repository_record(id: 11, name: 'docs', full_name: 'alice/docs', language: nil)
    database.execute(<<~SQL, [period_start, 10, 10])
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city, owner_country,
        stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', ?, 1, 'alice', 'Kraków', 'Poland', ?, 1, '2026-06-01T00:00:00Z')
    SQL
    database.execute(<<~SQL, [period_start, 11, 5])
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city, owner_country,
        stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', ?, 1, 'alice', 'Kraków', 'Poland', ?, 1, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_repository_record(id:, name:, full_name:, language:)
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO repositories(
          platform, github_id, owner_github_id, owner_login, name, full_name, html_url, language, fork, archived,
          updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        'github', id, 1, 'alice', name, full_name,
        "https://github.com/#{full_name}", language, 0, 0, '2026-06-01T00:00:00Z'
      ]
    )
  end

  def seed_organization_stats(period_start)
    database.execute(<<~SQL, [period_start])
      INSERT INTO organization_monthly_stats(
        period_start, platform, organization_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, members_count, updated_at
      )
      VALUES (?, 'github', 2, 'org', 'Warszawa', 'Poland', 1, 20, 2, 1, 3, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_organization_repository_stats(period_start)
    seed_organization_repository_record(id: 20, name: 'tool', full_name: 'org/tool', language: 'Ruby')
    seed_organization_repository_record(id: 21, name: 'docs', full_name: 'org/docs', language: nil)
    database.execute(<<~SQL, [period_start, 20, 20])
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', ?, 2, 'org', 'Warszawa', 'Poland', ?, 2, '2026-06-01T00:00:00Z')
    SQL
    database.execute(<<~SQL, [period_start, 21, 10])
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, 'github', ?, 2, 'org', 'Warszawa', 'Poland', ?, 2, '2026-06-01T00:00:00Z')
    SQL
  end

  def seed_organization_repository_record(id:, name:, full_name:, language:)
    database.execute(
      <<~SQL,
        INSERT OR IGNORE INTO organization_repositories(
          platform, github_id, organization_github_id, organization_login, name, full_name, html_url, language, fork,
          archived, updated_at
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL
      [
        'github', id, 2, 'org', name, full_name,
        "https://github.com/#{full_name}", language, 0, 0, '2026-06-01T00:00:00Z'
      ]
    )
  end

  def seed_package_run(period_start, ecosystem: 'npm', status: 'finished')
    database.execute(<<~SQL, [period_start, ecosystem, status])
      INSERT INTO package_crawl_runs(period_start, ecosystem, status, started_at, finished_at, updated_at)
      VALUES (?, ?, ?, '2026-06-01T00:00:00Z', '2026-06-01T00:10:00Z', '2026-06-01T00:10:00Z')
    SQL
  end

  def failing_badge_materializer
    Object.new.tap do |materializer|
      materializer.define_singleton_method(:materialize) { |*_args, **_kwargs| raise 'badge materialization failed' }
    end
  end
end

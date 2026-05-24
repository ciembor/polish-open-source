# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration do
  it 'bootstraps a fresh database with the current schema' do
    database = open_database

    described_class.new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql).bootstrap!

    expect(database.fetch_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'users'")).to eq(1)
    expect(
      database.fetch_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'crawl_job_runs'")
    ).to eq(1)
    expect(database.fetch_value(package_table_sql('job_work_events'))).to eq(1)
    expect(database.fetch_value(package_table_sql('package_crawl_runs'))).to eq(1)
    expect(database.fetch_value(package_table_sql('registry_package_snapshots'))).to eq(1)
    expect(database.table_info('users').map { |column| column.fetch('name') }).to include('platform')
  end

  it 'creates package ranking tables and indexes in a fresh database' do
    database = open_database

    described_class.new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql).bootstrap!

    expect(package_tables(database)).to include(
      'package_crawl_runs',
      'package_repository_scans',
      'package_manifests',
      'registry_packages',
      'registry_package_links',
      'registry_package_snapshots'
    )
    expect(package_indexes(database)).to include(
      'idx_package_repository_scans_status_period',
      'idx_package_manifests_ecosystem_name',
      'idx_registry_package_snapshots_ecosystem_downloads',
      'idx_registry_package_snapshots_ecosystem_dependents'
    )
  end

  it 'migrates a legacy GitHub-only database to platform-qualified records' do
    database = open_database
    database.execute_batch(legacy_schema_sql)
    database.execute(
      'INSERT INTO users(github_id, login, html_url, updated_at) VALUES(1, ?, ?, ?)',
      ['alice', 'https://github.com/alice', 'now']
    )

    described_class.new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql).bootstrap!

    expect(database.fetch_value('SELECT platform FROM users WHERE github_id = 1')).to eq('github')
    expect(database.table_info('users').map { |column| column.fetch('name') }).to include('platform')
  end

  it 'rolls back a failed legacy migration before old tables are dropped' do
    database = open_database
    database.execute_batch(legacy_schema_sql)
    database.execute(
      'INSERT INTO users(github_id, login, html_url, updated_at) VALUES(1, ?, ?, ?)',
      ['alice', 'https://github.com/alice', 'now']
    )

    migration = described_class.new(database, 'CREATE TABLE users(broken')

    expect { migration.bootstrap! }.to raise_error(StandardError)
    expect(table_exists?(database, 'users')).to be(true)
    expect(table_exists?(database, 'users_old')).to be(false)
    expect(database.fetch_value('SELECT login FROM users WHERE github_id = 1')).to eq('alice')
    expect(database.fetch_value('PRAGMA foreign_keys')).to eq(1)
  end

  it 'keeps bootstrapping idempotent when the schema is current' do
    database = open_database
    migration = described_class.new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)

    migration.bootstrap!

    expect { migration.bootstrap! }.not_to raise_error
    expect(database.fetch_value("SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'users'")).to eq(1)
  end

  def open_database
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
  end

  def table_exists?(database, table_name)
    !database.fetch_value(
      "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table_name]
    ).nil?
  end

  def package_table_sql(table_name)
    "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '#{table_name}'"
  end

  def package_tables(database)
    database.fetch_all(<<~SQL).map { |row| row.fetch(:name) }
      SELECT name FROM sqlite_master
      WHERE type = 'table' AND name LIKE 'package_%' OR name LIKE 'registry_package%'
    SQL
  end

  def package_indexes(database)
    database.fetch_all(<<~SQL).map { |row| row.fetch(:name) }
      SELECT name FROM sqlite_master
      WHERE type = 'index' AND name LIKE 'idx_package_%' OR name LIKE 'idx_registry_package%'
    SQL
  end

  def legacy_schema_sql
    <<~SQL
      CREATE TABLE sync_runs (id INTEGER PRIMARY KEY AUTOINCREMENT, period_start TEXT NOT NULL UNIQUE,
        period_end TEXT NOT NULL, status TEXT NOT NULL, started_at TEXT NOT NULL, finished_at TEXT, error TEXT);
      CREATE TABLE candidate_users (period_start TEXT NOT NULL, github_id INTEGER NOT NULL, login TEXT NOT NULL,
        source_query TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'pending', error TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL, PRIMARY KEY(period_start, login));
      CREATE TABLE users (github_id INTEGER PRIMARY KEY, login TEXT NOT NULL UNIQUE, name TEXT, location_raw TEXT,
        city TEXT, country TEXT, email TEXT, homepage TEXT, html_url TEXT NOT NULL, avatar_url TEXT, updated_at TEXT NOT NULL);
      CREATE TABLE user_monthly_stats (period_start TEXT NOT NULL, user_github_id INTEGER NOT NULL, login TEXT NOT NULL,
        city TEXT, country TEXT, public_repo_count INTEGER NOT NULL, total_stars INTEGER NOT NULL,
        monthly_stars_delta INTEGER NOT NULL, public_activity_count INTEGER NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY(period_start, user_github_id));
      CREATE TABLE repositories (github_id INTEGER PRIMARY KEY, owner_github_id INTEGER NOT NULL,
        owner_login TEXT NOT NULL, name TEXT NOT NULL, full_name TEXT NOT NULL UNIQUE, description TEXT,
        html_url TEXT NOT NULL, homepage TEXT, language TEXT, fork INTEGER NOT NULL, archived INTEGER NOT NULL,
        updated_at TEXT NOT NULL);
      CREATE TABLE repository_monthly_stats (period_start TEXT NOT NULL, repository_github_id INTEGER NOT NULL,
        owner_github_id INTEGER NOT NULL, owner_login TEXT NOT NULL, owner_city TEXT, owner_country TEXT,
        stargazers_count INTEGER NOT NULL, monthly_stars_delta INTEGER NOT NULL, updated_at TEXT NOT NULL,
        PRIMARY KEY(period_start, repository_github_id));
    SQL
  end
end

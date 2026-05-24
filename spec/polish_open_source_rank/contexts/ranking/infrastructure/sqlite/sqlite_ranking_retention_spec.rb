# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingRetention do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:retention) { described_class.new(database) }

  it 'keeps all ranked users while retaining repositories with at least five stars' do
    101.times do |index|
      id = index + 1
      login = format('user%03d', id)
      repo_id = id + 1000
      seed_user(id, login)
      seed_user_stats(id, login, total_stars: id, delta: id, activity: id)
      seed_repository(repo_id, id, login, "#{login}/app")
      seed_repository_stats(repo_id, id, login, stars: id, delta: id)
    end
    seed_repository(3001, 101, 'user101', 'user101/tiny')
    seed_repository_stats(3001, 101, 'user101', stars: 4, delta: 4)

    retention.prune(period)

    expect(database.fetch_value('SELECT COUNT(*) FROM user_monthly_stats')).to eq(101)
    expect(database.fetch_value('SELECT COUNT(*) FROM repository_monthly_stats')).to eq(97)
    expect(database.fetch_value('SELECT 1 FROM users WHERE github_id = ?', [1])).to eq(1)
    expect(database.fetch_value('SELECT 1 FROM repositories WHERE github_id = ?', [1001])).to be_nil
    expect(database.fetch_value('SELECT 1 FROM repositories WHERE github_id = ?', [3001])).to be_nil
  end

  it 'keeps all ranked organizations while retaining organization repositories with at least five stars' do
    seed_organization(201, 'polish-org')
    seed_organization_stats(201, 'polish-org', total_stars: 10, delta: 1)
    seed_organization_repository(2001, 201, 'polish-org', 'polish-org/app')
    seed_organization_repository_stats(2001, 201, 'polish-org', stars: 5, delta: 1)
    seed_organization_repository(2002, 201, 'polish-org', 'polish-org/tiny')
    seed_organization_repository_stats(2002, 201, 'polish-org', stars: 4, delta: 1)

    retention.prune(period)

    expect(database.fetch_value('SELECT COUNT(*) FROM organization_monthly_stats')).to eq(1)
    expect(database.fetch_value('SELECT COUNT(*) FROM organization_repository_monthly_stats')).to eq(1)
    expect(database.fetch_value('SELECT 1 FROM organizations WHERE github_id = ?', [201])).to eq(1)
    expect(database.fetch_value('SELECT 1 FROM organization_repositories WHERE github_id = ?', [2001])).to eq(1)
    expect(database.fetch_value('SELECT 1 FROM organization_repositories WHERE github_id = ?', [2002])).to be_nil
  end

  def seed_user(id, login)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
  end

  def seed_user_stats(id, login, total_stars:, delta:, activity:)
    database.execute(
      user_stats_sql,
      [
        period.start_date.to_s, 'github', id, login, 'Kraków', 'Poland', 1, total_stars, delta, activity,
        '2026-05-01T00:10:00Z'
      ]
    )
  end

  def seed_repository(id, owner_id, owner_login, full_name)
    database.execute(
      repository_sql,
      [
        'github', id, owner_id, owner_login, full_name.split('/').last, full_name,
        "https://github.com/#{full_name}", 0, 0, '2026-05-01T00:01:00Z'
      ]
    )
  end

  def seed_repository_stats(id, owner_id, owner_login, stars:, delta:)
    database.execute(
      repository_stats_sql,
      [
        period.start_date.to_s, 'github', id, owner_id, owner_login, 'Kraków', 'Poland', stars, delta,
        '2026-05-01T00:10:00Z'
      ]
    )
  end

  def seed_organization(id, login)
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:01:00Z']
    )
  end

  def seed_organization_stats(id, login, total_stars:, delta:)
    database.execute(
      organization_stats_sql,
      [period.start_date.to_s, 'github', id, login, 'Warszawa', 'Poland', 1, total_stars, delta,
       '2026-05-01T00:10:00Z']
    )
  end

  def seed_organization_repository(id, organization_id, organization_login, full_name)
    database.execute(
      organization_repository_sql,
      [
        'github', id, organization_id, organization_login, full_name.split('/').last, full_name,
        "https://github.com/#{full_name}", 0, 0, '2026-05-01T00:01:00Z'
      ]
    )
  end

  def seed_organization_repository_stats(id, organization_id, organization_login, stars:, delta:)
    database.execute(
      organization_repository_stats_sql,
      [
        period.start_date.to_s, 'github', id, organization_id, organization_login, 'Warszawa', 'Poland',
        stars, delta, '2026-05-01T00:10:00Z'
      ]
    )
  end

  def user_stats_sql
    <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, public_activity_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def repository_sql
    <<~SQL
      INSERT INTO repositories(
        platform, github_id, owner_github_id, owner_login, name, full_name, html_url, fork, archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def repository_stats_sql
    <<~SQL
      INSERT INTO repository_monthly_stats(
        period_start, platform, repository_github_id, owner_github_id, owner_login, owner_city,
        owner_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def organization_stats_sql
    <<~SQL
      INSERT INTO organization_monthly_stats(
        period_start, platform, organization_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def organization_repository_sql
    <<~SQL
      INSERT INTO organization_repositories(
        platform, github_id, organization_github_id, organization_login, name, full_name,
        html_url, fork, archived, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def organization_repository_stats_sql
    <<~SQL
      INSERT INTO organization_repository_monthly_stats(
        period_start, platform, repository_github_id, organization_github_id, organization_login,
        organization_city, organization_country, stargazers_count, monthly_stars_delta, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end
end

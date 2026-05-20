# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteRankingReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:read_model) { described_class.new(database) }

  it 'returns scoped user and repository rankings with stable tie breakers' do
    seed_user(id: 1, login: 'alice', city: 'Kraków', total_stars: 30, delta: 0, activity: 10)
    seed_user(id: 2, login: 'bob', city: 'Wrocław', total_stars: 30, delta: 4, activity: 5)
    seed_repository(
      id: 10, owner_id: 1, owner: 'alice', full_name: 'alice/app', city: 'Kraków', stars: 50, delta: 0
    )
    seed_repository(
      id: 20, owner_id: 2, owner: 'bob', full_name: 'bob/app', city: 'Wrocław', stars: 60, delta: 6
    )

    expect(read_model.user_rankings('poland', period_start: period).fetch(:top).map { _1.fetch(:login) }).to eq(
      %w[alice bob]
    )
    expect(read_model.user_rankings('krakow', period_start: period).fetch(:active).map { _1.fetch(:login) }).to eq(
      ['alice']
    )
    expect(read_model.repository_rankings('poland', period_start: period).fetch(:trending).map do |row|
      row.fetch(:full_name)
    end).to eq(['bob/app'])
  end

  it 'bounds requested ranking limits' do
    seed_user(id: 1, login: 'alice', city: 'Kraków', total_stars: 30, delta: 0, activity: 10)

    expect(read_model.ranked_users('poland', period, 'total_stars', limit: 0).length).to eq(1)
  end

  it 'binds scope params as flat positional SQL parameters' do
    capturing_database = new_capturing_database
    read_model = described_class.new(capturing_database)

    read_model.ranked_repositories('krakow', period, 'stargazers_count')
    read_model.ranked_users('krakow', period, 'total_stars')

    expect(capturing_database.calls[0]).to include(
      sql: include('stats.owner_city = ?'), params: %w[2026-04-01 Kraków]
    )
    expect(capturing_database.calls[1]).to include(
      sql: include('stats.city = ?'), params: %w[2026-04-01 Kraków]
    )
  end

  it 'bounds ranking limits inside generated SQL' do
    capturing_database = new_capturing_database
    read_model = described_class.new(capturing_database)

    read_model.ranked_users('poland', period, 'total_stars', limit: '1000; DROP TABLE users')
    read_model.ranked_users('poland', period, 'total_stars', limit: 0)

    expect(capturing_database.calls[0].fetch(:sql)).to match(/LIMIT 100\n\z/)
    expect(capturing_database.calls[1].fetch(:sql)).to match(/LIMIT 1\n\z/)
  end

  def period
    '2026-04-01'
  end

  def seed_user(id:, login:, city:, total_stars:, delta:, activity:)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', id, login, "https://github.com/#{login}", '2026-05-01T00:00:00Z']
    )
    database.execute(user_stats_sql, [period, 'github', id, login, city, 'Poland', 1, total_stars, delta, activity,
                                      '2026-05-01T00:00:00Z'])
  end

  def seed_repository(attributes)
    database.execute(repository_sql, ['github', attributes.fetch(:id), attributes.fetch(:owner_id),
                                      attributes.fetch(:owner), attributes.fetch(:full_name).split('/').last,
                                      attributes.fetch(:full_name), 0, 0,
                                      '2026-05-01T00:00:00Z'])
    database.execute(repository_stats_sql, [period, 'github', attributes.fetch(:id), attributes.fetch(:owner_id),
                                            attributes.fetch(:owner), attributes.fetch(:city), 'Poland',
                                            attributes.fetch(:stars), attributes.fetch(:delta),
                                            '2026-05-01T00:00:00Z'])
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
      VALUES (?, ?, ?, ?, ?, ?, 'https://example.com/repo', ?, ?, ?)
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

  def new_capturing_database
    Struct.new(:calls) do
      def fetch_all(sql, params)
        calls << { sql: sql, params: params }
        []
      end
    end.new([])
  end
end

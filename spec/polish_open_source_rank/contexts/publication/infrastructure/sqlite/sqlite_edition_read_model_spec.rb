# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Publication::Infrastructure::SQLite::SQLiteEditionReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end

  it 'returns only years that have public ranking records' do
    read_model = described_class.new(database)

    seed_run('2026-04-01')
    seed_run('2025-04-01')
    seed_user_stats('2026-04-01')

    expect(read_model.years).to eq([{ year: '2026' }])
    expect(read_model.edition_years).to eq([{ year: '2026' }])
  end

  it 'builds monthly editions from the ranking read model' do
    ranking_read_model = new_capturing_ranking_read_model
    read_model = described_class.new(database, ranking_read_model: ranking_read_model)

    seed_run('2026-04-01')
    seed_user_stats('2026-04-01')

    expect(read_model.monthly_editions(2026, scope: 'krakow')).to eq(
      [
        {
          period_start: '2026-04-01',
          repositories: [:repository_rows],
          users_by_stars: [:star_rows],
          users_by_merged_prs: [:activity_rows]
        }
      ]
    )
    expect(ranking_read_model.calls).to eq(
      [
        [:repositories, 'krakow', '2026-04-01', :repository_top, 3],
        [:users, 'krakow', '2026-04-01', :user_top, 3],
        [:users, 'krakow', '2026-04-01', :user_active, 3]
      ]
    )
  end

  def seed_run(period_start)
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at, finished_at) VALUES (?, ?, ?, ?, ?)',
      [period_start, '2026-05-01', 'finished', '2026-05-01T00:00:00Z', '2026-05-01T00:30:00Z']
    )
  end

  def seed_user_stats(period_start)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
    database.execute(user_stats_sql, [period_start, 'github', 1, 'alice', 'Kraków', 'Poland', 1, 10, 2, 3,
                                      '2026-05-01T00:10:00Z'])
  end

  def user_stats_sql
    <<~SQL
      INSERT INTO user_monthly_stats(
        period_start, platform, user_github_id, login, city, country, public_repo_count,
        total_stars, monthly_stars_delta, merged_pull_requests_count, updated_at
      )
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    SQL
  end

  def new_capturing_ranking_read_model
    Struct.new(:calls) do
      def ranked_repository_metric(scope, period_start, metric_key, limit:)
        calls << [:repositories, scope, period_start, metric_key, limit]
        [:repository_rows]
      end

      def ranked_user_metric(scope, period_start, metric_key, limit:)
        calls << [:users, scope, period_start, metric_key, limit]
        metric_key == :user_top ? [:star_rows] : [:activity_rows]
      end
    end.new([])
  end
end

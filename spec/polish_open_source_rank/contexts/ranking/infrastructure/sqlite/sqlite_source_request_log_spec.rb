# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSourceRequestLog do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'rank.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 1, 12, 0, 0) } }
  let(:log) { described_class.new(database, clock: clock) }

  it 'records source API requests with an injectable timestamp' do
    log.record_api_request(platform: 'github', path: '/users/alice', status: 200)
    log.record_api_request(
      platform: 'gitlab',
      path: '/users/bob',
      status: 429,
      recorded_at: Time.utc(2026, 5, 1, 12, 1, 0)
    )

    expect(request_events).to contain_exactly(
      include(platform: 'github', path: '/users/alice', status: 200, recorded_at: '2026-05-01T12:00:00Z'),
      include(platform: 'gitlab', path: '/users/bob', status: 429, recorded_at: '2026-05-01T12:01:00Z')
    )
  end

  def request_events
    database.fetch_all('SELECT platform, path, status, recorded_at FROM api_request_events ORDER BY id')
  end
end

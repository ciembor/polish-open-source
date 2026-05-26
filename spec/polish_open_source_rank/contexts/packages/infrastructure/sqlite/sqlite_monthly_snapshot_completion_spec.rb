# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLiteMonthlySnapshotCompletion do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'monthly-completion.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }
  let(:completion) { described_class.new(database) }

  it 'reports monthly completion only for finished sync runs in the requested period' do
    expect(completion.complete?(period)).to be(false)

    seed_sync_run('2026-04-01', status: 'running')

    expect(completion.complete?(period)).to be(false)

    database.dataset(:sync_runs).where(period_start: '2026-04-01').update(status: 'finished')

    expect(completion.complete?(period)).to be(true)
    expect(completion.complete?(PolishOpenSourceRank::Shared::Domain::Period.parse('2026-05'))).to be(false)
  end

  def seed_sync_run(period_start, status:)
    database.dataset(:sync_runs).insert(
      period_start: period_start,
      period_end: '2026-05-01',
      status: status,
      started_at: '2026-05-02T01:15:00Z'
    )
  end
end

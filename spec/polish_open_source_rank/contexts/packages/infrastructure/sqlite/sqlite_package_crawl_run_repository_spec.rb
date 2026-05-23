# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageCrawlRunRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'packages.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 23, 10, 15, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'creates package crawl runs and marks them as finished' do
    run_id = repository.create(period, ecosystem: 'npm', refresh: true)

    repository.finish(run_id)

    expect(run(run_id)).to include(
      period_start: '2026-04-01',
      ecosystem: 'npm',
      status: 'finished',
      refresh: 1,
      started_at: '2026-05-23T10:15:00Z',
      finished_at: '2026-05-23T10:15:00Z',
      error: nil,
      updated_at: '2026-05-23T10:15:00Z'
    )
  end

  it 'returns the active run for duplicate period and ecosystem starts' do
    first_id = repository.create(period, ecosystem: 'rubygems', refresh: false)
    second_id = repository.create(period, ecosystem: 'rubygems', refresh: true)

    expect(second_id).to eq(first_id)
    expect(database.fetch_value('SELECT COUNT(*) FROM package_crawl_runs')).to eq(1)
    expect(run(first_id)).to include(refresh: 0, status: 'running')
  end

  it 'allows a new run after the previous one has finished' do
    first_id = repository.create(period, ecosystem: nil, refresh: false)
    repository.finish(first_id)

    second_id = repository.create(period, ecosystem: nil, refresh: false)

    expect(second_id).not_to eq(first_id)
    expect(database.fetch_value('SELECT COUNT(*) FROM package_crawl_runs')).to eq(2)
  end

  it 'records failed runs and rejects unsupported ecosystems' do
    run_id = repository.create(period, ecosystem: 'crates', refresh: false)

    repository.fail(run_id, 'registry timeout')

    expect(run(run_id)).to include(status: 'failed', error: 'registry timeout')
    expect do
      repository.create(period, ecosystem: 'unknown', refresh: false)
    end.to raise_error(ArgumentError, 'Unsupported package ecosystem: unknown')
  end

  def run(run_id)
    database.fetch_all('SELECT * FROM package_crawl_runs WHERE id = ?', [run_id]).first
  end
end

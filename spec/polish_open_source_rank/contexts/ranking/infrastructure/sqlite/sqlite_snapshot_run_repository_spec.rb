# frozen_string_literal: true

class FakeSnapshotRunDatabase
  attr_reader :executions, :values

  def initialize(*results)
    @results = results
    @executions = []
    @values = []
  end

  def execute(sql, params)
    executions << [sql, params]
  end

  def get_first_value(sql, params)
    values << [sql, params]
    @results.shift
  end
end

RSpec.describe PolishOpenSourceRank::Contexts::Ranking::Infrastructure::SQLite::SQLiteSnapshotRunRepository do
  let(:period) { PolishOpenSourceRank::Shared::Domain::Period.parse('2026-04') }

  it 'creates runs with UTC timestamps and positional database params', :aggregate_failures do
    database = FakeSnapshotRunDatabase.new(nil, 123)
    lifecycle = described_class.new(database)
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }

    expect(lifecycle.create(period)).to eq(123)
    expect(database.executions.size).to eq(3)
    expect(database.executions.first.first).to include('INSERT INTO sync_runs')
    expect(database.executions.first.last).to eq(['2026-04-01', '2026-05-01', '2026-04-01T10:00:00Z'])
    expect(database.executions[1].first).to include('UPDATE candidate_users')
    expect(database.executions[1].first).to include("status = 'failed'")
    expect(database.executions[1].last).to eq(['2026-04-01T10:00:00Z', '2026-04-01'])
    expect(database.executions[2].first).to include('UPDATE candidate_users')
    expect(database.executions[2].first).to include("status = 'processed'")
    expect(database.executions[2].first).to include('repository_monthly_stats')
    expect(database.executions[2].last).to eq(['2026-04-01T10:00:00Z', '2026-04-01'])
    expect(database.values.last.first).to include('SELECT id FROM sync_runs')
    expect(database.values.last.last).to eq(['2026-04-01'])
  end

  it 'does not reopen finished runs without retryable candidates' do
    database = FakeSnapshotRunDatabase.new(1)
    lifecycle = described_class.new(database)

    expect(lifecycle.create(period)).to be_nil
    expect(database.values.first.first).to include("status = 'finished'")
    expect(database.values.first.first).to include('NOT EXISTS')
    expect(database.values.first.first).to include("status IN ('pending', 'failed')")
    expect(database.values.first.first).to include("status = 'processed'")
    expect(database.values.first.last).to eq(['2026-04-01'])
    expect(database.executions).to be_empty
  end

  it 'marks runs as failed with the original error message' do
    database = FakeSnapshotRunDatabase.new
    lifecycle = described_class.new(database)

    lifecycle.fail(12, 'GitHubClient::Forbidden: blocked')

    expect(database.executions.first.first).to eq("UPDATE sync_runs SET status = 'failed', error = ? WHERE id = ?")
    expect(database.executions.first.last).to eq(['GitHubClient::Forbidden: blocked', 12])
  end

  it 'marks runs as finished with a UTC timestamp' do
    database = FakeSnapshotRunDatabase.new
    lifecycle = described_class.new(database)
    allow(Time).to receive(:now) { Time.new(2026, 4, 1, 12, 0, 0, '+02:00') }

    lifecycle.finish(12)

    expect(database.executions.first.first)
      .to eq("UPDATE sync_runs SET status = 'finished', finished_at = ? WHERE id = ?")
    expect(database.executions.first.last).to eq(['2026-04-01T10:00:00Z', 12])
  end

  it 'reports retryable candidates through the lifecycle query' do
    database = FakeSnapshotRunDatabase.new(1, nil)
    lifecycle = described_class.new(database)

    expect(lifecycle.retryable_candidates?(period)).to be(true)
    expect(lifecycle.retryable_candidates?(period)).to be(false)
    expect(database.values.first.first).to include("status IN ('pending', 'failed')")
    expect(database.values.first.first).to include("status = 'processed'")
    expect(database.values).to all(satisfy { |(_, params)| params == ['2026-04-01'] })
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'events.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end

  it 'records job work events for operational progress and duration estimates' do
    described_class.new(database).record(
      period_start: '2026-04-01',
      job_kind: 'monthly',
      stage: 'users',
      unit_kind: 'user_candidate',
      platform: 'github',
      ecosystem: nil,
      subject_id: 1,
      subject_label: 'alice',
      status: 'processed',
      started_at: '2026-05-01T00:00:00Z',
      finished_at: '2026-05-01T00:00:02Z',
      duration_ms: 2000
    )

    expect(database.fetch_all('SELECT * FROM job_work_events').first).to include(
      period_start: '2026-04-01',
      job_kind: 'monthly',
      stage: 'users',
      unit_kind: 'user_candidate',
      platform: 'github',
      subject_id: '1',
      subject_label: 'alice',
      status: 'processed',
      duration_ms: 2000
    )
  end

  it 'drops retryable SQLite lock errors from telemetry writes' do
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    repository = described_class.new(database)

    allow(database).to receive(:transaction)
      .and_raise(Sequel::DatabaseError, 'SQLite3::BusyException: database is locked')

    expect do
      repository.record(
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'users',
        unit_kind: 'user_candidate',
        platform: 'github',
        subject_label: 'alice',
        status: 'processed',
        started_at: '2026-05-01T00:00:00Z',
        finished_at: '2026-05-01T00:00:02Z',
        duration_ms: 2000
      )
    end.not_to raise_error
  end

  it 'reraises non-retryable telemetry write failures' do
    database = instance_double(PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database)
    repository = described_class.new(database)

    allow(database).to receive(:transaction)
      .and_raise(Sequel::DatabaseError, 'SQLite3::ConstraintException: no such table')

    expect do
      repository.record(
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: 'users',
        unit_kind: 'user_candidate',
        platform: 'github',
        subject_label: 'alice',
        status: 'processed',
        started_at: '2026-05-01T00:00:00Z',
        finished_at: '2026-05-01T00:00:02Z',
        duration_ms: 2000
      )
    end.to raise_error(Sequel::DatabaseError, /no such table/)
  end

  it 'touches the heartbeat when recording timed work events' do
    heartbeat = instance_double(PolishOpenSourceRank::Contexts::Operations::Application::ProgressHeartbeat, touch: nil)
    repository = described_class.new(database, heartbeat: heartbeat)

    repository.record_timed(
      period_start: '2026-04-01',
      job_kind: 'monthly',
      stage: 'users',
      unit_kind: 'user_candidate',
      platform: 'github',
      subject_label: 'alice'
    ) { :processed }

    expect(heartbeat).to have_received(:touch).at_least(:twice)
  end
end

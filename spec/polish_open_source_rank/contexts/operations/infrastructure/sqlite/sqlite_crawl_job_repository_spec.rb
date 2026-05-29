# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'crawl.sqlite3')
    ).tap do |sqlite|
      sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    end
  end
  let(:clock) { -> { Time.utc(2026, 5, 22, 21, 40, 0) } }
  let(:repository) { described_class.new(database, clock: clock) }

  it 'records started jobs and marks them as finished' do
    job_id = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])

    repository.finish(job_id)

    expect(job(job_id)).to include(
      command: 'monthly_rankings',
      arguments_json: '["--month","2026-04"]',
      status: 'finished',
      attempts: 1,
      started_at: '2026-05-22T21:40:00Z',
      finished_at: '2026-05-22T21:40:00Z',
      error: nil
    )
  end

  it 'reopens unfinished jobs with the same command and arguments' do
    first_id = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])
    repository.fail(first_id, 'RuntimeError: boom', status: 'interrupted')

    second_id = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])

    expect(second_id).to eq(first_id)
    expect(job(first_id)).to include(
      status: 'running',
      attempts: 2,
      finished_at: nil,
      error: nil
    )
  end

  it 'lists only resumable jobs with parsed arguments' do
    running = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])
    finished = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-05'])
    repository.finish(finished)
    interrupted = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-06'])
    repository.fail(interrupted, 'Received SIGTERM', status: 'interrupted')

    expect(repository.resumable).to match(
      [
        a_hash_including(id: running, command: 'monthly_rankings', arguments: ['--month', '2026-04']),
        a_hash_including(id: interrupted, command: 'monthly_rankings', arguments: ['--month', '2026-06'])
      ]
    )
  end

  it 'lists every crawl job in reverse start order' do
    older = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])
    newer = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-05'])

    expect(repository.all.map { |job| job.fetch(:id) }).to eq([newer, older])
  end

  it 'increments attempts and keeps the job running when retrying a transient failure' do
    job_id = repository.start(command: 'monthly_rankings', arguments: ['--month', '2026-04'])

    repository.retry(job_id, 'Net::OpenTimeout: execution expired')

    expect(job(job_id)).to include(
      status: 'running',
      attempts: 2,
      error: 'Net::OpenTimeout: execution expired',
      finished_at: nil
    )
  end

  def job(job_id)
    database.fetch_all('SELECT * FROM crawl_job_runs WHERE id = ?', [job_id]).first
  end
end

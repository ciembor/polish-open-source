# frozen_string_literal: true

require 'open3'

RSpec.describe Pathname do
  describe 'production_alert_monitor.py' do
    it 'detects stalled jobs, request failures, slow p95 latency and SQLite retry spikes' do
      database_path = File.join(Dir.mktmpdir, 'monitor.sqlite3')
      state_path = File.join(Dir.mktmpdir, 'monitor-state.json')
      journal_output = File.join(Dir.mktmpdir, 'journal.log')
      journalctl_path = File.join(Dir.mktmpdir, 'fake-journalctl.py')
      script_path = PolishOpenSourceRank.root.join('scripts/production_alert_monitor.py')

      seed_database(database_path)
      File.write(journal_output, fake_events.join("\n"))
      File.write(
        journalctl_path,
        <<~PYTHON
          #!/usr/bin/env python3
          from pathlib import Path
          print(Path(#{journal_output.inspect}).read_text(), end="")
        PYTHON
      )
      File.chmod(0o755, journalctl_path)

      stdout, stderr, status = Open3.capture3(
        monitor_env(database_path, state_path, journalctl_path),
        'python3',
        script_path.to_s
      )

      expect(status.success?).to be(true), stderr

      payload = JSON.parse(stdout)

      expect(payload.fetch('alerts').map { |alert| alert.fetch('key') }).to contain_exactly(
        'http_5xx_spike',
        'http_p95_latency_high',
        'monthly_stalled',
        'sqlite_retry_spike'
      )
      expect(payload.fetch('delivery')).to eq('sentry_events' => [])
      expect(JSON.parse(File.read(state_path)).fetch('alerts').map { |alert| alert.fetch('key') }).to eq(
        payload.fetch('alerts').map { |alert| alert.fetch('key') }
      )
    end
  end

  def seed_database(path)
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(path)
    database.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    database.execute(
      'INSERT INTO sync_runs(period_start, period_end, status, started_at) VALUES (?, ?, ?, ?)',
      ['2026-04-01', '2026-05-01', 'running', (Time.now.utc - (45 * 60)).iso8601]
    )
  end

  def fake_events
    [
      { event: 'http_request', status: 200, latency_ms: 120.0 },
      { event: 'http_request', status: 500, latency_ms: 1800.0 },
      { event: 'http_request', status: 200, latency_ms: 1600.0 },
      { event: 'sqlite_write_retry', attempts: 1, lock_wait_ms: 900.0, backoff_ms: 250.0 },
      { event: 'sqlite_write_retry', attempts: 2, lock_wait_ms: 1200.0, backoff_ms: 500.0 }
    ].map { |event| JSON.generate(event) }
  end

  def monitor_env(database_path, state_path, journalctl_path)
    {
      'DATABASE_URL' => "sqlite://#{database_path}",
      'SENTRY_DSN' => '',
      'PRODUCTION_ALERT_STATE_PATH' => state_path,
      'PRODUCTION_ALERT_JOURNALCTL' => journalctl_path,
      'PRODUCTION_ALERT_JOB_STALE_MINUTES' => '30',
      'PRODUCTION_ALERT_LOG_WINDOW_MINUTES' => '10',
      'PRODUCTION_ALERT_HTTP_5XX_THRESHOLD' => '1',
      'PRODUCTION_ALERT_HTTP_MIN_REQUESTS' => '1',
      'PRODUCTION_ALERT_P95_LATENCY_MS_THRESHOLD' => '1000',
      'PRODUCTION_ALERT_SQLITE_RETRY_THRESHOLD' => '2'
    }
  end
end

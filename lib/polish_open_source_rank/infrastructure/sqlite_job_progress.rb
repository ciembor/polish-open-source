# frozen_string_literal: true

require 'sequel'

module PolishOpenSourceRank
  module Infrastructure
    class SQLiteJobProgress
      STALE_SECONDS = 10 * 60
      MONTHLY_PLATFORM_ORDER = %w[github gitlab codeberg].freeze
      PACKAGE_STAGE_ORDER = %w[
        repository_scan
        manifest_parse
        registry_resolve
        registry_snapshot
      ].freeze
      RECENT_ERRORS_SQL = <<~SQL
        SELECT job_kind, stage, unit_kind, platform, ecosystem, subject_label, error, finished_at
        FROM job_work_events
        WHERE error IS NOT NULL
        ORDER BY datetime(finished_at) DESC, id DESC
        LIMIT 30
      SQL

      def initialize(database, stale_seconds: STALE_SECONDS)
        @database = database
        @stale_seconds = stale_seconds
      end

      def call(now: Time.now.utc)
        run = current_run
        package_run = current_package_run
        period_start = run&.fetch(:period_start) || package_run&.fetch(:period_start)

        {
          generated_at: now.iso8601,
          run: run&.slice(:period_start, :period_end, :status, :started_at, :finished_at, :error),
          package_run: package_run&.slice(:period_start, :ecosystem, :status, :started_at, :finished_at, :error),
          platforms: [],
          progress_points: [],
          request_points: request_points(run || package_run, now),
          sections: period_start ? sections(period_start, now) : [],
          recent_events: recent_events,
          recent_errors: fetch_all(RECENT_ERRORS_SQL)
        }
      end

      private

      attr_reader :database, :stale_seconds

      def current_run
        sync_runs_dataset
          .select(:period_start, :period_end, :status, :started_at, :finished_at, :error)
          .order(Sequel.desc(Sequel.function(:datetime, :started_at)), Sequel.desc(:period_start))
          .first
      end

      def current_package_run
        return unless table?(:package_crawl_runs)

        package_crawl_runs_dataset
          .select(:period_start, :ecosystem, :status, :started_at, :finished_at, :error)
          .order(Sequel.desc(Sequel.function(:datetime, :started_at)), Sequel.desc(:id))
          .first
      end

      def sections(period_start, now)
        monthly_sections(period_start, now) + package_sections(period_start, now)
      end

      def monthly_sections(period_start, now)
        candidate_sections = MONTHLY_PLATFORM_ORDER.flat_map do |platform|
          [
            user_candidate_section(period_start, platform, now),
            organization_candidate_section(period_start, platform, now)
          ]
        end.compact
        candidate_sections + repository_sections(period_start, now)
      end

      def user_candidate_section(period_start, platform, now)
        counts = candidate_counts(:candidate_users, period_start, platform)
        return if counts.fetch(:total).zero?

        section(
          label: "monthly users / #{platform}",
          period_start: period_start,
          job_kind: 'monthly',
          stage: 'users',
          unit_kind: 'user_candidate',
          platform: platform,
          total: counts.fetch(:total),
          done: counts.fetch(:done),
          pending: counts.fetch(:pending),
          failed: counts.fetch(:failed),
          skipped: counts.fetch(:skipped),
          status_detail: nil,
          now: now
        )
      end

      def organization_candidate_section(period_start, platform, now)
        counts = candidate_counts(:candidate_organizations, period_start, platform)
        return if counts.fetch(:total).zero?

        section(
          label: "monthly organizations / #{platform}",
          period_start: period_start,
          job_kind: 'monthly',
          stage: 'organizations',
          unit_kind: 'organization_candidate',
          platform: platform,
          total: counts.fetch(:total),
          done: counts.fetch(:done),
          pending: counts.fetch(:pending),
          failed: counts.fetch(:failed),
          skipped: counts.fetch(:skipped),
          status_detail: nil,
          now: now
        )
      end

      def repository_sections(period_start, now)
        SQLiteRepositoryJobProgressSections
          .new(database: database, finished_sync_run: method(:finished_sync_run?), section_builder: method(:section))
          .call(period_start, now)
      end

      def package_sections(period_start, now)
        SQLitePackageJobProgressSections
          .new(database: database, section_builder: method(:section))
          .call(period_start, now)
      end

      def section(attributes)
        event_stats = work_event_stats(attributes)
        pending = attributes.fetch(:pending)
        average_ms = event_stats.fetch(:average_ms)
        p95_ms = event_stats.fetch(:p95_ms)
        {
          **attributes.except(:now, :period_start),
          throughput_per_minute: event_stats.fetch(:throughput_per_minute),
          average_ms: average_ms,
          median_ms: event_stats.fetch(:median_ms),
          p95_ms: p95_ms,
          eta_average_seconds: eta_seconds(pending, average_ms),
          eta_p95_seconds: eta_seconds(pending, p95_ms),
          last_finished_at: event_stats.fetch(:last_finished_at),
          state: section_state(attributes, event_stats),
          stale: stale?(event_stats.fetch(:last_finished_at), attributes.fetch(:now))
        }
      end

      def work_event_stats(attributes)
        events = work_events_for(attributes)
        durations = events.map { |event| event.fetch(:duration_ms).to_i }.sort
        {
          throughput_per_minute: throughput_per_minute(events),
          average_ms: average(durations),
          median_ms: percentile(durations, 0.50),
          p95_ms: percentile(durations, 0.95),
          last_finished_at: events.map { |event| event.fetch(:finished_at) }.max
        }
      end

      def work_events_for(attributes)
        dataset = job_work_events_dataset.where(
          period_start: attributes.fetch(:period_start),
          job_kind: attributes.fetch(:job_kind),
          stage: attributes.fetch(:stage),
          unit_kind: attributes.fetch(:unit_kind)
        )
        dataset = dataset.where(platform: attributes[:platform]) if attributes[:platform]
        dataset = dataset.where(ecosystem: attributes[:ecosystem]) if attributes[:ecosystem]
        dataset.select(:duration_ms, :finished_at).order(:finished_at).all
      end

      def throughput_per_minute(events)
        return 0.0 if events.length < 2

        started = Time.parse(events.first.fetch(:finished_at))
        finished = Time.parse(events.last.fetch(:finished_at))
        minutes = [(finished - started) / 60.0, 1.0 / 60.0].max
        (events.length / minutes).round(2)
      end

      def average(values)
        return nil if values.empty?

        (values.sum.to_f / values.length).round
      end

      def percentile(values, percentile)
        return nil if values.empty?

        values[[(values.length * percentile).ceil - 1, 0].max]
      end

      def eta_seconds(pending, duration_ms)
        return nil unless duration_ms&.positive?

        ((pending.to_i * duration_ms) / 1000.0).round
      end

      def stale?(last_finished_at, now)
        return false unless last_finished_at

        (now - Time.parse(last_finished_at)) > stale_seconds
      end

      def section_state(attributes, event_stats)
        return 'failed' if failed_monthly_run_with_pending_work?(attributes)
        return package_section_state(attributes) if package_section?(attributes)
        return 'pending' if attributes.fetch(:pending).positive? && !event_stats.fetch(:last_finished_at)
        return 'running' if attributes.fetch(:pending).positive?
        return 'failed' if attributes.fetch(:failed).positive?

        'complete'
      end

      def failed_monthly_run_with_pending_work?(attributes)
        attributes[:job_kind] == 'monthly' &&
          failed_sync_run?(attributes.fetch(:period_start)) &&
          attributes.fetch(:pending).positive?
      end

      def package_section?(attributes)
        attributes[:job_kind] == 'packages'
      end

      def package_section_state(attributes)
        return 'failed' if attributes.fetch(:failed).positive?
        return 'complete' unless attributes.fetch(:pending).positive?

        case latest_package_run_status(attributes.fetch(:period_start))
        when 'running' then 'running'
        when 'failed' then 'failed'
        else 'pending'
        end
      end

      def latest_package_run_status(period_start)
        package_crawl_runs_dataset
          .where(period_start: period_start)
          .order(Sequel.desc(Sequel.function(:datetime, :started_at)), Sequel.desc(:id))
          .get(:status)
      end

      def failed_sync_run?(period_start)
        sync_runs_dataset.where(period_start: period_start, status: 'failed').any?
      end

      def finished_sync_run?(period_start)
        sync_runs_dataset.where(period_start: period_start, status: 'finished').any?
      end

      def candidate_counts(table, period_start, platform)
        rows = database.dataset(table).where(period_start: period_start, platform: platform)
        total = rows.count
        pending = rows.where(status: 'pending').count
        failed = rows.where(status: 'failed').count
        skipped = rows.where(status: %w[rejected missing]).count
        { total: total, done: total - pending, pending: pending, failed: failed, skipped: skipped }
      end

      def request_points(run, now)
        return [] unless run

        finished_at = run[:finished_at] || now.iso8601
        fetch_all(<<~SQL, [run.fetch(:started_at), finished_at])
          SELECT platform, substr(recorded_at, 1, 16) || ':00Z' AS minute,
                 COUNT(*) AS requests_count,
                 SUM(CASE WHEN status >= 400 THEN 1 ELSE 0 END) AS error_count
          FROM api_request_events
          WHERE recorded_at >= ? AND recorded_at <= ?
          GROUP BY platform, minute
          ORDER BY platform, minute
        SQL
      end

      def recent_events
        fetch_all(<<~SQL)
          SELECT job_kind AS platform, stage AS source, subject_label AS subject,
                 status AS detail, finished_at AS recorded_at
          FROM job_work_events
          ORDER BY datetime(finished_at) DESC, id DESC
          LIMIT 30
        SQL
      end

      def fetch_all(sql, params = [])
        database.fetch_all(sql, params)
      end

      def table?(name)
        database.fetch_value(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?",
          [name.to_s]
        ) == 1
      end

      def sync_runs_dataset
        database.dataset(:sync_runs)
      end

      def package_crawl_runs_dataset
        database.dataset(:package_crawl_runs)
      end

      def job_work_events_dataset
        database.dataset(:job_work_events)
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe(
  PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteRepositoryJobProgressSections
) do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'repository-progress.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end
  let(:section_builder) { ->(attributes) { attributes } }

  it 'builds user and organization repository sections from processed repository work' do
    seed_user_stats(public_repo_count: 2)
    seed_organization_stats(public_repo_count: 2)
    seed_work_event(stage: 'user_repository', status: 'stored', subject_label: 'alice/app')
    seed_work_event(stage: 'user_repository', status: 'skipped', subject_label: 'alice/lib')
    seed_work_event(stage: 'organization_repository', status: 'failed', subject_label: 'org/tool')

    sections = described_class
               .new(
                 database: database,
                 finished_sync_run: ->(_period_start) { false },
                 section_builder: section_builder
               )
               .call('2026-04-01', Time.parse('2026-05-01T00:10:00Z'))

    expect(sections).to include(
      include(
        label: 'user repositories / github',
        total: 2,
        done: 2,
        pending: 0,
        failed: 0,
        status_detail: 'stored=1, skipped=1, failed=0'
      ),
      include(
        label: 'organization repositories / github',
        total: 2,
        done: 0,
        pending: 1,
        failed: 1,
        status_detail: 'stored=0, skipped=0, failed=1'
      )
    )
  end

  it 'returns no sections without repository stats or work events and completes finished runs' do
    empty_sections = described_class
                     .new(database: database, finished_sync_run: ->(_period_start) { false },
                          section_builder: section_builder)
                     .call('2026-04-01', Time.parse('2026-05-01T00:10:00Z'))

    expect(empty_sections).to eq([])

    seed_user_stats(public_repo_count: 2)

    finished_sections = described_class
                        .new(database: database, finished_sync_run: ->(_period_start) { true },
                             section_builder: section_builder)
                        .call('2026-04-01', Time.parse('2026-05-01T00:10:00Z'))

    expect(finished_sections).to include(
      include(
        label: 'user repositories / github',
        total: 2,
        done: 2,
        pending: 0,
        failed: 0,
        status_detail: 'stored=0, skipped=0, failed=0'
      )
    )
  end

  def seed_user_stats(public_repo_count:)
    database.execute(
      'INSERT INTO users(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 1, 'alice', 'https://github.com/alice', '2026-05-01T00:01:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO user_monthly_stats(
          period_start, platform, user_github_id, login, public_repo_count, total_stars,
          monthly_stars_delta, merged_pull_requests_count, updated_at
        )
        VALUES (?, ?, ?, ?, ?, 0, 0, 0, ?)
      SQL
      ['2026-04-01', 'github', 1, 'alice', public_repo_count, '2026-05-01T00:01:00Z']
    )
  end

  def seed_organization_stats(public_repo_count:)
    database.execute(
      'INSERT INTO organizations(platform, github_id, login, html_url, updated_at) VALUES (?, ?, ?, ?, ?)',
      ['github', 3, 'org', 'https://github.com/org', '2026-05-01T00:01:00Z']
    )
    database.execute(
      <<~SQL,
        INSERT INTO organization_monthly_stats(
          period_start, platform, organization_github_id, login, public_repo_count,
          total_stars, monthly_stars_delta, updated_at
        )
        VALUES (?, ?, ?, ?, ?, 0, 0, ?)
      SQL
      ['2026-04-01', 'github', 3, 'org', public_repo_count, '2026-05-01T00:01:00Z']
    )
  end

  def seed_work_event(stage:, status:, subject_label:)
    PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteJobWorkEventRepository
      .new(database)
      .record(
        period_start: '2026-04-01',
        job_kind: 'monthly',
        stage: stage,
        unit_kind: 'repository',
        platform: 'github',
        subject_label: subject_label,
        status: status,
        started_at: '2026-05-01T00:00:00Z',
        finished_at: '2026-05-01T00:00:01Z',
        duration_ms: 1000
      )
  end
end

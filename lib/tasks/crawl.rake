# frozen_string_literal: true

namespace :crawl do
  desc 'Run a monthly crawl: rake crawl:monthly[2026-04,github,organizations,false,false]'
  task :monthly, %i[month platform scope refresh use_stars_diff] do |_task, args|
    PolishOpenSourceRank::Interfaces::Composition::RankingJobFactory.build(monthly_argv(args)).call
  end

  desc 'Run a package crawl: rake crawl:packages[2026-04,npm,100,false]'
  package_args = %i[period ecosystem limit refresh repository_limit scan_limit manifest_limit registry_limit]
  task :packages, package_args do |_task, args|
    PolishOpenSourceRank::Interfaces::Composition::PackageRankingJobFactory.build(package_argv(args)).call
  end

  desc 'Resume interrupted crawl jobs'
  task :resume do
    PolishOpenSourceRank::Interfaces::Composition::CrawlResumerFactory.build.call
  end

  desc 'List tracked crawl jobs'
  task :list do
    crawl_job_repository.all.each { |job| puts format_crawl_job(job) }
  end

  desc 'Reset interrupted package repository scans: rake crawl:repair_packages[2026-04]'
  task :repair_packages, [:period] do |_task, args|
    period = PolishOpenSourceRank::Shared::Domain::Period.parse(args[:period])
    count = package_repository_queue.reset_stale_processing(period, older_than: 0)
    puts "Reset #{count} interrupted package repository scans for #{period.key}"
  end
end

def package_argv(args)
  argv = package_value_arguments(args)
  argv << '--refresh' if args[:refresh] == 'true'
  argv
end

def package_value_arguments(args)
  [
    ['--period', args[:period]],
    ['--ecosystem', args[:ecosystem]],
    ['--limit', args[:limit]],
    ['--repository-limit', args[:repository_limit]],
    ['--scan-limit', args[:scan_limit]],
    ['--manifest-limit', args[:manifest_limit]],
    ['--registry-limit', args[:registry_limit]]
  ].flat_map { |flag, value| value ? [flag, value] : [] }
end

def monthly_argv(args)
  argv = []
  argv += ['--month', args[:month]] if args[:month]
  argv += ['--platform', args[:platform]] if args[:platform]
  argv += ['--scope', args[:scope]] if args[:scope]
  argv << '--refresh' if args[:refresh] == 'true'
  argv << '--use-stars-diff' if args[:use_stars_diff] == 'true'
  argv
end

def crawl_job_repository
  PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository.new(database)
end

def package_repository_queue
  PolishOpenSourceRank::Contexts::Packages::Infrastructure::SQLite::SQLitePackageRepositoryQueue.new(database)
end

def database
  @database ||= begin
    configuration = PolishOpenSourceRank::Configuration.load
    sqlite = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
    PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration
      .new(sqlite, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
      .bootstrap!
    sqlite
  end
end

def format_crawl_job(job)
  [
    job.fetch(:id),
    job.fetch(:status),
    job.fetch(:command),
    job.fetch(:arguments).join(' '),
    "attempts=#{job.fetch(:attempts)}",
    "started_at=#{job.fetch(:started_at)}",
    ("finished_at=#{job[:finished_at]}" if job[:finished_at]),
    ("error=#{job[:error]}" if job[:error])
  ].compact.join(' | ')
end

# frozen_string_literal: true

namespace :crawl do
  desc 'Run a monthly crawl: rake crawl:monthly[2026-04,github,organizations,false]'
  task :monthly, %i[month platform scope refresh] do |_task, args|
    PolishOpenSourceRank::Interfaces::Composition::RankingJobFactory.build(monthly_argv(args)).call
  end

  desc 'Run a package crawl: rake crawl:packages[2026-04,npm,100,false]'
  task :packages, %i[period ecosystem limit refresh] do |_task, args|
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
end

def package_argv(args)
  argv = []
  argv += ['--period', args[:period]] if args[:period]
  argv += ['--ecosystem', args[:ecosystem]] if args[:ecosystem]
  argv += ['--limit', args[:limit]] if args[:limit]
  argv << '--refresh' if args[:refresh] == 'true'
  argv
end

def monthly_argv(args)
  argv = []
  argv += ['--month', args[:month]] if args[:month]
  argv += ['--platform', args[:platform]] if args[:platform]
  argv += ['--scope', args[:scope]] if args[:scope]
  argv << '--refresh' if args[:refresh] == 'true'
  argv
end

def crawl_job_repository
  configuration = PolishOpenSourceRank::Configuration.load
  database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(configuration.database_path)
  PolishOpenSourceRank::Infrastructure::PlatformSchemaMigration
    .new(database, PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql)
    .bootstrap!
  PolishOpenSourceRank::Contexts::Operations::Infrastructure::SQLite::SQLiteCrawlJobRepository.new(database)
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

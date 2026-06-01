#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'time'

require_relative '../lib/polish_open_source_rank'

Query = Struct.new(:name, :sql, :params, keyword_init: true)

options = {
  database_path: nil,
  period: nil,
  format: 'markdown'
}

OptionParser.new do |parser|
  parser.banner = 'Usage: scripts/public_query_plans.rb [options]'
  parser.on('--database PATH', 'SQLite database path; defaults to PUBLIC_DATABASE_URL or DATABASE_URL') do |value|
    options[:database_path] = value.delete_prefix('sqlite://')
  end
  parser.on('--period YYYY-MM-DD', 'Published period to inspect; defaults to latest published period') do |value|
    options[:period] = value
  end
end.parse!

configuration = PolishOpenSourceRank::Configuration.load
database_path = options[:database_path] || configuration.public_database_path
database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(database_path, readonly: true)
publication_table_exists = database.fetch_value(
  "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'public_snapshot_publications'"
) == 1
period = options[:period]
period ||= if publication_table_exists
             database.fetch_value(
               <<~SQL
                 SELECT period_start
                 FROM public_snapshot_publications
                 WHERE status = 'published'
                 ORDER BY period_start DESC
                 LIMIT 1
               SQL
             )
           else
             database.fetch_value("SELECT MAX(period_start) FROM sync_runs WHERE status = 'finished'")
           end
abort 'No published period found. Publish a snapshot first or pass --period YYYY-MM-DD.' unless period

queries = []

if publication_table_exists
  queries << Query.new(
    name: 'latest period resolution',
    sql: "SELECT MAX(period_start) FROM public_snapshot_publications WHERE status = 'published'",
    params: []
  )
end

queries.push(
  Query.new(
    name: 'people ranking',
    sql: <<~SQL,
      SELECT users.platform, users.login, stats.total_stars
      FROM user_monthly_stats stats
      INNER JOIN users ON users.platform = stats.platform AND users.github_id = stats.user_github_id
      WHERE stats.period_start = ? AND stats.country = ?
      ORDER BY stats.total_stars DESC, users.platform ASC, users.login COLLATE NOCASE ASC
      LIMIT 100
    SQL
    params: [period, 'Poland']
  ),
  Query.new(
    name: 'repository ranking',
    sql: <<~SQL,
      SELECT repositories.platform, repositories.full_name, stats.stargazers_count
      FROM repository_monthly_stats stats
      INNER JOIN repositories
        ON repositories.platform = stats.platform
       AND repositories.github_id = stats.repository_github_id
      WHERE stats.period_start = ? AND stats.owner_country = ?
      ORDER BY stats.stargazers_count DESC, repositories.platform ASC, repositories.full_name COLLATE NOCASE ASC
      LIMIT 100
    SQL
    params: [period, 'Poland']
  ),
  Query.new(
    name: 'organization ranking',
    sql: <<~SQL,
      SELECT organizations.platform, organizations.login, stats.total_stars
      FROM organization_monthly_stats stats
      INNER JOIN organizations
        ON organizations.platform = stats.platform
       AND organizations.github_id = stats.organization_github_id
      WHERE stats.period_start = ? AND stats.country = ?
      ORDER BY stats.total_stars DESC, organizations.platform ASC, organizations.login COLLATE NOCASE ASC
      LIMIT 100
    SQL
    params: [period, 'Poland']
  ),
  Query.new(
    name: 'user profile',
    sql: <<~SQL,
      SELECT users.platform, users.login, stats.total_stars
      FROM users
      INNER JOIN user_monthly_stats stats
        ON stats.platform = users.platform
       AND stats.user_github_id = users.github_id
       AND stats.period_start = ?
      WHERE users.platform = ? AND users.login = ?
      LIMIT 1
    SQL
    params: [period, 'github', 'alice']
  ),
  Query.new(
    name: 'language index',
    sql: <<~SQL,
      SELECT repositories.language, COUNT(*) AS repositories_count, SUM(stats.stargazers_count) AS stars
      FROM repository_monthly_stats stats
      INNER JOIN repositories
        ON repositories.platform = stats.platform
       AND repositories.github_id = stats.repository_github_id
      WHERE stats.period_start = ?
        AND stats.owner_country = ?
        AND repositories.language IS NOT NULL
      GROUP BY repositories.language
      ORDER BY repositories_count DESC, repositories.language COLLATE NOCASE ASC
      LIMIT 100
    SQL
    params: [period, 'Poland']
  ),
  Query.new(
    name: 'package ranking',
    sql: <<~SQL,
      SELECT snapshots.ecosystem, snapshots.normalized_package_name, snapshots.downloads_30d
      FROM registry_package_snapshots snapshots
      WHERE snapshots.period_start = ? AND snapshots.ecosystem = ?
      ORDER BY snapshots.downloads_30d DESC, snapshots.normalized_package_name COLLATE NOCASE ASC
      LIMIT 100
    SQL
    params: [period, 'npm']
  ),
  Query.new(
    name: 'badge profile lookup',
    sql: <<~SQL,
      SELECT users.platform, users.login, stats.total_stars
      FROM users
      INNER JOIN user_monthly_stats stats
        ON stats.platform = users.platform
       AND stats.user_github_id = users.github_id
       AND stats.period_start = ?
      WHERE users.platform = ? AND users.login = ?
      LIMIT 1
    SQL
    params: [period, 'github', 'alice']
  )
)

puts '# Public query plans'
puts
puts "- generated_at: #{Time.now.utc.iso8601}"
puts "- database: #{database_path}"
puts "- period: #{period}"
puts

queries.each do |query|
  puts "## #{query.name}"
  puts
  database.fetch_all("EXPLAIN QUERY PLAN #{query.sql}", query.params).each do |row|
    puts "- #{row.fetch(:detail)}"
  end
  puts
end

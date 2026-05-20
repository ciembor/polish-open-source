# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

RSpec.describe 'architecture dependency rules' do
  def files_under(path)
    Dir[File.join(PolishOpenSourceRank.root, path, '**/*.rb')]
  end

  def file_body(path)
    File.read(path, encoding: 'UTF-8')
  end

  def relative_path(path)
    path.delete_prefix("#{PolishOpenSourceRank.root}/")
  end

  it 'keeps new domain code independent from outer layers', :aggregate_failures do
    forbidden = /\b(Infrastructure::|Web::|Sinatra|SQLite3|Net::HTTP|Discordrb|ENV\b)/
    domain_files = files_under('lib/polish_open_source_rank/shared/domain') +
                   files_under('lib/polish_open_source_rank/contexts/*/domain')

    expect(domain_files).not_to be_empty
    domain_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references an outer-layer dependency"
    end
  end

  it 'keeps new application code from instantiating mechanisms', :aggregate_failures do
    forbidden = /\b(SQLite3|Sinatra|Net::HTTP|Discordrb|ENV\b)/
    application_files = files_under('lib/polish_open_source_rank/contexts/*/application')

    application_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references an outer-layer mechanism"
    end
  end

  it 'keeps ranking use cases from speaking SQLite column names', :aggregate_failures do
    forbidden = /\b(github_id|user_github_id|repository_github_id|stargazers_count)\b/
    application_files = files_under('lib/polish_open_source_rank/contexts/ranking/application')

    application_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} exposes persistence names in a use case"
    end
  end

  it 'keeps production code off old compatibility namespaces', :aggregate_failures do
    forbidden = /
      \bApplication::MonthPeriod\b|
      \bApplication::MonthlySnapshotJob\b|
      (?<!Ranking::)\bApplication::SourceNotFound\b|
      \bPolishOpenSourceRank::Domain::LocationCatalog\b|
      \bPolishOpenSourceRank::Domain::LocationClassifier\b
    /x
    compatibility_files = %w[
      lib/polish_open_source_rank/application/month_period.rb
      lib/polish_open_source_rank/application/monthly_snapshot_job.rb
      lib/polish_open_source_rank/application/source_not_found.rb
      lib/polish_open_source_rank/domain/location_catalog.rb
      lib/polish_open_source_rank/domain/location_classifier.rb
    ]
    production_files = files_under('lib/polish_open_source_rank').reject do |path|
      compatibility_files.include?(relative_path(path))
    end

    production_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references an old compatibility namespace"
    end
  end

  it 'keeps web routes from bypassing publication queries', :aggregate_failures do
    forbidden = /
      \bstore\.
      (
        user_rankings|repository_rankings|user_profile|repository_profile|
        edition_years|monthly_editions|discord_access|discord_connection
      )\b
    /x
    web_files = files_under('lib/polish_open_source_rank/web')

    web_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} bypasses publication application queries"
    end
  end
end

# rubocop:enable RSpec/DescribeClass

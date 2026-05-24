# frozen_string_literal: true

# rubocop:disable RSpec/DescribeClass

RSpec.describe 'architecture dependency rules' do
  def files_under(path)
    Dir[File.join(PolishOpenSourceRank.root, path, '**/*.rb')]
  end

  def file_body(path)
    File.read(path, encoding: 'UTF-8')
  end

  it 'keeps new domain code independent from outer layers', :aggregate_failures do
    forbidden = /\b(Infrastructure::|Web::|Sinatra|SQLite3|Sequel|Net::HTTP|Discordrb|ENV\b)/
    domain_files = files_under('lib/polish_open_source_rank/shared/domain') +
                   files_under('lib/polish_open_source_rank/contexts/*/domain')

    expect(domain_files).not_to be_empty
    domain_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references an outer-layer dependency"
    end
  end

  it 'keeps new application code from instantiating mechanisms', :aggregate_failures do
    forbidden = /\b(SQLite3|Sequel|Sinatra|Net::HTTP|Discordrb|ENV\b)/
    application_files = files_under('lib/polish_open_source_rank/contexts/*/application')

    application_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references an outer-layer mechanism"
    end
  end

  it 'keeps application use cases inside bounded contexts' do
    expect(files_under('lib/polish_open_source_rank/application')).to be_empty
  end

  it 'keeps ranking use cases from speaking SQLite column names', :aggregate_failures do
    forbidden = /\b(github_id|user_github_id|repository_github_id|stargazers_count)\b/
    application_files = files_under('lib/polish_open_source_rank/contexts/ranking/application')

    application_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} exposes persistence names in a use case"
    end
  end

  it 'keeps community use cases from speaking SQLite identity column names', :aggregate_failures do
    forbidden = /\b(github_id|user_github_id)\b/
    application_files = files_under('lib/polish_open_source_rank/contexts/community/application')

    application_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} exposes persistence identity names in a use case"
    end
  end

  it 'keeps production code off old compatibility namespaces', :aggregate_failures do
    forbidden = /
      \bApplication::MonthPeriod\b|
      \bApplication::MonthlySnapshotJob\b|
      (?<!Ranking::)\bApplication::SourceNotFound\b|
      \bPolishOpenSourceRank::Domain::LocationCatalog\b|
      \bPolishOpenSourceRank::Domain::LocationClassifier\b|
      \bWeb::Auth::DiscordGateway\b|
      \bWeb::Auth::DiscordWelcomeMessage\b
    /x
    compatibility_files = %w[
      lib/polish_open_source_rank/web/auth/discord_gateway.rb
      lib/polish_open_source_rank/web/auth/discord_welcome_message.rb
    ]
    production_files = files_under('lib/polish_open_source_rank').reject do |path|
      compatibility_files.include?(path.delete_prefix("#{PolishOpenSourceRank.root}/"))
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
      )\b|
      \bSQLiteStore\b
    /x
    web_files = files_under('lib/polish_open_source_rank/web')

    web_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} bypasses publication application queries"
    end
  end

  it 'keeps production composition off the SQLiteStore facade', :aggregate_failures do
    forbidden = /\bSQLiteStore\b/
    production_files = files_under('lib/polish_open_source_rank') + files_under('bin')

    production_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references the SQLiteStore facade"
    end
  end

  it 'keeps low-level SQLite gateway details behind infrastructure seams', :aggregate_failures do
    forbidden = /\bSQLite3::Database\b|\bget_first_value\b|\bexecute_batch\b/
    compatibility_files = %w[
      lib/polish_open_source_rank/shared/infrastructure/sqlite/database.rb
      lib/polish_open_source_rank/infrastructure/platform_schema_migration.rb
    ]
    production_files = files_under('lib/polish_open_source_rank').reject do |path|
      compatibility_files.include?(path.delete_prefix("#{PolishOpenSourceRank.root}/"))
    end

    production_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} reaches through the SQLite infrastructure seam"
    end
  end

  it 'keeps Sequel confined to infrastructure adapters', :aggregate_failures do
    forbidden = /\bSequel\b|require ['"]sequel['"]/
    infrastructure_files = files_under('lib/polish_open_source_rank/infrastructure') +
                           files_under('lib/polish_open_source_rank/shared/infrastructure') +
                           files_under('lib/polish_open_source_rank/contexts/*/infrastructure')
    production_files = files_under('lib/polish_open_source_rank') - infrastructure_files

    production_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} references Sequel outside infrastructure"
    end
  end
end

# rubocop:enable RSpec/DescribeClass

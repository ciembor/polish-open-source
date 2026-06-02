# frozen_string_literal: true

module ArchitectureDependencyRules
end

RSpec.describe ArchitectureDependencyRules do
  def files_under(path)
    Dir[File.join(PolishOpenSourceRank.root, path, '**/*.rb')]
  end

  def file_body(path)
    File.read(path, encoding: 'UTF-8')
  end

  def sqlite_schema
    file_body(PolishOpenSourceRank.root.join('lib/polish_open_source_rank/infrastructure/sqlite_schema.sql'))
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

  it 'keeps Sinatra bootstrapping out of Web::App request flow' do
    app = file_body(PolishOpenSourceRank.root.join('lib/polish_open_source_rank/web/app.rb'))

    expect(app).not_to include('use Rack::Session::Cookie')
    expect(app).not_to include('register Routes::')
    expect(app).not_to include('HTML_REVISION_FILES')
  end

  it 'keeps Web::App routed through context-specific composition collaborators' do
    app = file_body(PolishOpenSourceRank.root.join('lib/polish_open_source_rank/web/app.rb'))

    expect(app).not_to include('def_delegators :composition')
  end

  it 'keeps web request handlers off composition read-model seams', :aggregate_failures do
    forbidden = /\b(ranking_read_model|profile_read_model|package_ranking_read_model)\b/
    request_handler_files = files_under('lib/polish_open_source_rank/web/controllers') +
                            files_under('lib/polish_open_source_rank/web/routes') +
                            [PolishOpenSourceRank.root.join('lib/polish_open_source_rank/web/app.rb').to_s]

    request_handler_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} reaches through a composition read-model seam"
    end
  end

  it 'keeps web composition boundaries outside core policy', :aggregate_failures do
    forbidden = /\bPolishOpenSourceRank::Web::Composition\b|\bWeb::Composition\b/
    core_policy_files = files_under('lib/polish_open_source_rank/shared/domain') +
                        files_under('lib/polish_open_source_rank/contexts/*/domain') +
                        files_under('lib/polish_open_source_rank/contexts/*/application')

    core_policy_files.each do |path|
      expect(file_body(path)).not_to match(forbidden), "#{path} depends on the web composition boundary"
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

  it 'keeps SQLite table ownership visible in the schema', :aggregate_failures do
    allowed_contexts = %w[community languages operations packages publication ranking]
    tables = sqlite_schema.scan(/CREATE TABLE IF NOT EXISTS ([a-z_]+) \(/).flatten

    expect(tables).not_to be_empty
    tables.each do |table|
      owner = owner_for_table(table)

      expect(owner).to be_a(String), "#{table} has no @owner marker before its CREATE TABLE"
      expect(allowed_contexts).to include(owner), "#{table} has unknown owner #{owner.inspect}"
    end
  end

  def owner_for_table(table)
    owner_match = sqlite_schema.match(
      /(?:-- @owner (?<owner>[a-z_]+)\n(?:-- @readers [a-z_, ]+\n)?)CREATE TABLE IF NOT EXISTS #{table} \(/
    )

    owner_match&.[](:owner)
  end
end

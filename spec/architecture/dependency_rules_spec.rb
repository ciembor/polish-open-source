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
end

# rubocop:enable RSpec/DescribeClass

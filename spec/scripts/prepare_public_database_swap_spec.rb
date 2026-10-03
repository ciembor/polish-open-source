# frozen_string_literal: true

require 'open3'

RSpec.describe Pathname do
  it 'clears stale SQLite sidecars while preserving a stopped public database' do
    database_path = Pathname(Dir.mktmpdir).join('public.sqlite3')
    database = PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(database_path)
    database.execute_batch('CREATE TABLE editions (name TEXT); INSERT INTO editions VALUES (\'current\');')
    database.close
    Pathname("#{database_path}-wal").write('')
    Pathname("#{database_path}-shm").write('')

    script = PolishOpenSourceRank.root.join('scripts/prepare_public_database_swap.py')
    _stdout, stderr, status = Open3.capture3('python3', script.to_s, database_path.to_s)

    expect(status.success?).to be(true), stderr
    expect(Pathname("#{database_path}-wal")).not_to exist
    expect(Pathname("#{database_path}-shm")).not_to exist
    expect(SQLite3::Database.new(database_path.to_s).get_first_value('SELECT name FROM editions')).to eq('current')
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database do
  it 'creates parent directories and configures SQLite connection defaults' do
    path = File.join(Dir.mktmpdir, 'nested', 'rank.sqlite3')
    database = described_class.open(path)

    database.execute('CREATE TABLE records(id INTEGER PRIMARY KEY, name TEXT)')
    database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])
    row = database.fetch_all('SELECT name FROM records').first

    expect(File.file?(path)).to be(true)
    expect(row).to include(name: 'alice')
    expect(database.fetch_value('PRAGMA foreign_keys')).to eq(1)
    expect(database.fetch_value('PRAGMA busy_timeout')).to eq(120_000)
    expect(database.fetch_value('PRAGMA journal_mode')).to eq('wal')
    expect(database.fetch_value('PRAGMA synchronous')).to eq(1)
  end

  it 'rolls transactions back on failure' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    database.execute('CREATE TABLE records(name TEXT)')

    expect do
      database.transaction do
        database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])
        raise 'stop'
      end
    end.to raise_error(RuntimeError, 'stop')

    expect(database.fetch_value('SELECT COUNT(*) FROM records')).to eq(0)
  end

  it 'commits successful transactions and exposes table metadata' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    database.execute('CREATE TABLE records(name TEXT)')

    database.transaction do
      database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])
    end

    expect(database.fetch_value('SELECT COUNT(*) FROM records')).to eq(1)
    expect(database.table_info('records').map { |column| column.fetch('name') }).to include('name')
  end

  it 'retries transient SQLite transaction locks' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    connection = Class.new do
      attr_reader :attempts

      def initialize
        @attempts = 0
      end

      def transaction(*)
        @attempts += 1
        raise Sequel::DatabaseError, 'SQLite3::BusyException: database is locked' if attempts == 1

        yield
      end
    end.new

    allow(database).to receive(:sequel_connection).and_return(connection)
    allow(database).to receive(:sleep)

    expect { expect(database.transaction { :committed }).to eq(:committed) }
      .to output(/"event":"sqlite_write_retry".*"attempts":1/).to_stdout
    expect(connection.attempts).to eq(2)
  end

  it 'retries transient SQLite write locks outside transactions' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    attempts = 0

    allow(database).to receive(:sleep)

    result = nil
    expect do
      result = database.write do
        attempts += 1
        raise Sequel::DatabaseError, 'SQLite3::BusyException: database is locked' if attempts == 1

        :written
      end
    end.to output(/"event":"sqlite_write_retry".*"attempts":1/).to_stdout

    expect(result).to eq(:written)
    expect(attempts).to eq(2)
  end

  it 'keeps Sequel dataset reads working for text columns' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    database.execute('CREATE TABLE records(name TEXT)')
    database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])

    expect(database.dataset(:records).select_map(:name)).to eq(['alice'])
  end

  it 'executes raw SQL reads through Sequel with bind parameters' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    database.execute('CREATE TABLE records(id INTEGER PRIMARY KEY, name TEXT)')
    database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])

    expect(database.fetch_all('SELECT name FROM records WHERE id = ?', [1])).to eq([{ name: 'alice' }])
    expect(database.fetch_value('SELECT COUNT(*) FROM records WHERE name = ?', ['alice'])).to eq(1)
  end

  it 'executes raw SQL writes through Sequel with bind parameters' do
    database = described_class.open(File.join(Dir.mktmpdir, 'rank.sqlite3'))
    database.execute('CREATE TABLE records(id INTEGER PRIMARY KEY, name TEXT)')
    database.execute('INSERT INTO records(name) VALUES (?)', ['alice'])

    deleted_count = database.execute('DELETE FROM records WHERE name = ?', ['alice'])

    expect(deleted_count).to eq(1)
    expect(database.fetch_value('SELECT COUNT(*) FROM records')).to eq(0)
  end

  it 'opens read-only public snapshots with SQLite query_only enabled' do
    path = File.join(Dir.mktmpdir, 'rank.sqlite3')
    writable = described_class.open(path)
    writable.execute('CREATE TABLE records(name TEXT)')
    writable.execute('INSERT INTO records(name) VALUES (?)', ['alice'])
    writable.close

    readonly = described_class.open(path, readonly: true)

    expect(readonly.fetch_value('PRAGMA query_only')).to eq(1)
    expect(readonly.fetch_value('SELECT COUNT(*) FROM records')).to eq(1)
    expect { readonly.execute('INSERT INTO records(name) VALUES (?)', ['bob']) }.to raise_error(Sequel::DatabaseError)
  end
end

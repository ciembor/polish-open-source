# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Contexts::Languages::Infrastructure::SQLite::SQLiteLanguageRankingReadModel do
  let(:database) do
    PolishOpenSourceRank::Shared::Infrastructure::SQLite::Database.open(
      File.join(Dir.mktmpdir, 'language_rankings.sqlite3')
    ).tap { |sqlite| sqlite.execute_batch(PolishOpenSourceRank::Infrastructure::SQLiteSchema.sql) }
  end
  let(:read_model) { described_class.new(database) }
  let(:period) { '2026-04-01' }

  it 'ranks repository languages by project count, stars, and monthly trend' do
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 100, delta: 2)
    seed_user_repository(id: 2, full_name: 'alice/ruby-b', language: 'Ruby', stars: 5, delta: 0)
    seed_organization_repository(id: 3, full_name: 'org/typescript-a', language: 'TypeScript', stars: 90, delta: 8)
    seed_user_repository(id: 4, full_name: 'alice/go-a', language: 'Go', stars: 30, delta: 0)
    seed_user_repository(id: 5, full_name: 'alice/unknown', language: nil, stars: 200, delta: 10)

    rankings = read_model.rankings(period_start: period, limit: 10)

    expect(rankings.fetch(:repository_count).map { |row| row.fetch(:language) }).to eq(%w[Ruby Go TypeScript])
    expect(rankings.fetch(:repository_stars_count).map { |row| row.fetch(:language) }).to eq(%w[Ruby TypeScript Go])
    expect(rankings.fetch(:repository_stars_delta).map { |row| row.fetch(:language) }).to eq(%w[TypeScript Ruby])
    expect(rankings.fetch(:repository_count).first).to include(
      language: 'Ruby',
      repository_count: 2,
      repository_stars_count: 105,
      repository_stars_delta: 2
    )
  end

  it 'bounds limits and rejects unsupported metrics' do
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 100, delta: 2)

    expect(read_model.ranked_languages(period_start: period, metric: 'repository_count', limit: 0).length).to eq(1)
    expect do
      read_model.ranked_languages(period_start: period, metric: 'downloads')
    end.to raise_error(ArgumentError, 'Unsupported language ranking metric: downloads')
  end

  def seed_user_repository(id:, full_name:, language:, stars:, delta:)
    owner_id = source_owner_id(full_name)
    database.dataset(:users).insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' }).insert(
      platform: 'github',
      github_id: owner_id,
      login: full_name.split('/').first,
      html_url: "https://github.com/#{full_name.split('/').first}",
      updated_at: '2026-05-01T00:00:00Z'
    )
    database.dataset(:repositories).insert(repository_attributes(id, full_name, language).merge(
                                             owner_github_id: owner_id,
                                             owner_login: full_name.split('/').first
                                           ))
    database.dataset(:repository_monthly_stats).insert(
      period_start: period,
      platform: 'github',
      repository_github_id: id,
      owner_github_id: owner_id,
      owner_login: full_name.split('/').first,
      stargazers_count: stars,
      monthly_stars_delta: delta,
      updated_at: '2026-05-01T00:00:00Z'
    )
  end

  def seed_organization_repository(id:, full_name:, language:, stars:, delta:)
    owner_id = source_owner_id(full_name)
    database.dataset(:organizations).insert_conflict(target: %i[platform github_id], update: { updated_at: 'now' })
            .insert(
              platform: 'github',
              github_id: owner_id,
              login: full_name.split('/').first,
              html_url: "https://github.com/#{full_name.split('/').first}",
              updated_at: '2026-05-01T00:00:00Z'
            )
    database.dataset(:organization_repositories).insert(repository_attributes(id, full_name, language).merge(
                                                          organization_github_id: owner_id,
                                                          organization_login: full_name.split('/').first
                                                        ))
    database.dataset(:organization_repository_monthly_stats).insert(
      period_start: period,
      platform: 'github',
      repository_github_id: id,
      organization_github_id: owner_id,
      organization_login: full_name.split('/').first,
      stargazers_count: stars,
      monthly_stars_delta: delta,
      updated_at: '2026-05-01T00:00:00Z'
    )
  end

  def repository_attributes(id, full_name, language)
    {
      platform: 'github',
      github_id: id,
      name: full_name.split('/').last,
      full_name: full_name,
      html_url: "https://github.com/#{full_name}",
      language: language,
      fork: 0,
      archived: 0,
      updated_at: '2026-05-01T00:00:00Z'
    }
  end

  def source_owner_id(full_name)
    full_name.split('/').first.bytes.sum
  end
end

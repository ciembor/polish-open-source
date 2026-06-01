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
    expect(rankings.fetch(:repository_count).first).not_to include(:sample_repository_full_name)
  end

  it 'returns language cards ordered by repository count' do
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 100, delta: 2)
    seed_user_repository(id: 2, full_name: 'alice/ruby-b', language: 'Ruby', stars: 5, delta: 0)
    seed_organization_repository(id: 3, full_name: 'org/typescript-a', language: 'TypeScript', stars: 90, delta: 8)

    expect(read_model.language_cards(period_start: period)).to eq(
      [
        {
          language: 'Ruby',
          repository_count: 2,
          repository_stars_count: 105,
          repository_stars_delta: 2
        },
        {
          language: 'TypeScript',
          repository_count: 1,
          repository_stars_count: 90,
          repository_stars_delta: 8
        }
      ]
    )
  end

  it 'ranks repositories inside a language with a people and organizations split' do
    seed_language_repository_split

    user_rankings = read_model.repository_rankings(
      language: 'ruby',
      period_start: period,
      limit: 10,
      repository_kind: 'user'
    )
    organization_top = read_model.ranked_repositories(
      language: 'Ruby',
      period_start: period,
      metric: 'repository_stars_count',
      repository_kind: 'organization'
    )

    expect(user_rankings.fetch(:repository_stars_count).map { |row| row.fetch(:full_name) }).to eq(
      ['alice/ruby-a', 'alice/ruby-b']
    )
    expect(user_rankings.fetch(:repository_stars_delta).map { |row| row.fetch(:full_name) }).to eq(
      ['alice/ruby-b', 'alice/ruby-a']
    )
    expect(organization_top.first).to include(
      full_name: 'org/ruby-c',
      repository_kind: 'organization',
      repository_stars_count: 90
    )
  end

  it 'uses repository stats from the requested period for both user and organization rankings' do
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 10, delta: 1)
    seed_user_repository_stats(period_start: '2026-03-01', id: 1, full_name: 'alice/ruby-a', stars: 999, delta: 99)
    seed_organization_repository(id: 2, full_name: 'org/ruby-b', language: 'Ruby', stars: 20, delta: 2)
    seed_organization_repository_stats(
      period_start: '2026-03-01',
      id: 2,
      full_name: 'org/ruby-b',
      stars: 888,
      delta: 88
    )

    april = read_model.repository_rankings(language: 'Ruby', period_start: period, limit: 10)
    march = read_model.repository_rankings(language: 'Ruby', period_start: '2026-03-01', limit: 10)

    expect(april.fetch(:repository_stars_count).map(&method(:repository_star_totals)))
      .to eq([['org/ruby-b', 20], ['alice/ruby-a', 10]])
    expect(april.fetch(:repository_stars_delta).map(&method(:repository_star_deltas)))
      .to eq([['org/ruby-b', 2], ['alice/ruby-a', 1]])
    expect(march.fetch(:repository_stars_count).map(&method(:repository_star_totals)))
      .to eq([['alice/ruby-a', 999], ['org/ruby-b', 888]])
  end

  it 'bounds limits and rejects unsupported metrics' do
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 100, delta: 2)

    expect(read_model.ranked_languages(period_start: period, metric: 'repository_count', limit: 0).length).to eq(1)
    expect(read_model.ranked_repositories(period_start: period, language: 'Ruby', metric: 'repository_stars_count',
                                          limit: 0).length).to eq(1)
    expect do
      read_model.ranked_languages(period_start: period, metric: 'downloads')
    end.to raise_error(ArgumentError, 'Unsupported language ranking metric: downloads')
    expect do
      read_model.ranked_repositories(period_start: period, language: 'Ruby', metric: 'repository_count')
    end.to raise_error(ArgumentError, 'Unsupported language repository ranking metric: repository_count')
    expect do
      read_model.ranked_languages(period_start: period, metric: 'repository_count', repository_kind: 'team')
    end.to raise_error(ArgumentError, 'Unsupported language repository kind: team')
  end

  def seed_language_repository_split
    seed_user_repository(id: 1, full_name: 'alice/ruby-a', language: 'Ruby', stars: 100, delta: 2)
    seed_user_repository(id: 2, full_name: 'alice/ruby-b', language: 'Ruby', stars: 5, delta: 9)
    seed_organization_repository(id: 3, full_name: 'org/ruby-c', language: 'Ruby', stars: 90, delta: 8)
    seed_user_repository(id: 4, full_name: 'alice/go-a', language: 'Go', stars: 30, delta: 20)
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
      organization_repository_stats_attributes(
        period_start: period,
        id: id,
        full_name: full_name,
        stars: stars,
        delta: delta
      )
    )
  end

  def seed_user_repository_stats(period_start:, id:, full_name:, stars:, delta:)
    database.dataset(:repository_monthly_stats).insert(
      repository_stats_attributes(period_start: period_start, id: id, full_name: full_name, stars: stars, delta: delta)
    )
  end

  def seed_organization_repository_stats(period_start:, id:, full_name:, stars:, delta:)
    database.dataset(:organization_repository_monthly_stats).insert(
      organization_repository_stats_attributes(
        period_start: period_start,
        id: id,
        full_name: full_name,
        stars: stars,
        delta: delta
      )
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

  def repository_stats_attributes(period_start:, id:, full_name:, stars:, delta:)
    {
      period_start: period_start,
      platform: 'github',
      repository_github_id: id,
      owner_github_id: source_owner_id(full_name),
      owner_login: full_name.split('/').first,
      stargazers_count: stars,
      monthly_stars_delta: delta,
      updated_at: '2026-05-01T00:00:00Z'
    }
  end

  def organization_repository_stats_attributes(period_start:, id:, full_name:, stars:, delta:)
    {
      period_start: period_start,
      platform: 'github',
      repository_github_id: id,
      organization_github_id: source_owner_id(full_name),
      organization_login: full_name.split('/').first,
      stargazers_count: stars,
      monthly_stars_delta: delta,
      updated_at: '2026-05-01T00:00:00Z'
    }
  end

  def repository_star_totals(row)
    [row.fetch(:full_name), row.fetch(:repository_stars_count)]
  end

  def repository_star_deltas(row)
    [row.fetch(:full_name), row.fetch(:repository_stars_delta)]
  end
end

# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::RankingPaginator do
  it 'paginates rankings without a count query' do
    paginator = described_class.new('2')
    page = paginator.fetch do |limit:, offset:|
      expect([limit, offset]).to eq([101, 100])
      Array.new(101) { |index| { rank: offset + index + 1 } }
    end

    expect(page.records.length).to eq(100)
    expect(page.records.first).to eq(rank: 101)
    expect(page).to have_attributes(number: 2, offset: 100, previous_page: 1, next_page: 3)
  end

  it 'uses the first page by default and omits unavailable navigation' do
    page = described_class.new(nil).fetch { [{ rank: 1 }] }

    expect(page).to have_attributes(number: 1, offset: 0, previous_page: nil, next_page: nil)
  end

  it 'rejects malformed, excessive, and empty later pages' do
    expect { described_class.new('0') }.to raise_error(described_class::InvalidPage)
    expect { described_class.new('2.5') }.to raise_error(described_class::InvalidPage)
    expect { described_class.new('10001') }.to raise_error(described_class::InvalidPage)
    expect { described_class.new('2').fetch { [] } }.to raise_error(described_class::InvalidPage)
  end
end

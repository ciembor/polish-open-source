# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::BadgeHelpers do
  subject(:helper_host) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::BadgeHelpers
    end.new
  end

  it 'builds stable badge paths without profile SEO slugs', :aggregate_failures do
    expect(
      helper_host.user_badge_path(platform: 'github', login: 'ciembor', name: 'Maciej Ciemborowicz')
    ).to eq('/badges/users/github/ciembor.svg')
    expect(
      helper_host.organization_badge_path(platform: 'github', login: 'acme', name: 'Acme Labs')
    ).to eq('/badges/organizations/github/acme.svg')
    expect(
      helper_host.repository_badge_path(platform: 'github', full_name: 'ciembor/polish-open-source-rank')
    ).to eq('/badges/repositories/github/ciembor/polish-open-source-rank.svg')
  end
end

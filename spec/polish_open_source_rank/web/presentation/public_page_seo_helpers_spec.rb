# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::PublicPageSeoHelpers do
  subject(:host) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::PublicPageSeoHelpers

      def t(key, values = {})
        serialized = values.sort_by(&:first).map { |name, value| "#{name}=#{value}" }.join('|')
        return key if serialized.empty?

        "#{key}|#{serialized}"
      end

      def call(method_name, ...)
        send(method_name, ...)
      end
    end.new
  end

  it 'builds SEO text across profile variants', :aggregate_failures do
    expect(host.call(:user_profile_seo_description, { location_raw: 'Krakow, Poland' }, 'Jan Kowalski', 'GitHub')).to(
      eq('users.seo.description|location=Krakow, Poland|platform=GitHub|user=Jan Kowalski')
    )
    expect(host.call(:user_profile_seo_description, {}, 'alice', 'GitHub')).to eq(
      'users.seo.description_without_location|location=|platform=GitHub|user=alice'
    )
    expect(
      host.call(:repository_profile_seo_title, { full_name: 'alice/app', name: 'app', language: 'Ruby' }, 'GitHub')
    ).to eq(
      'repositories.seo.title|language=Ruby|platform=GitHub|repository=app'
    )
    expect(host.call(:repository_profile_seo_title, { full_name: 'alice/app' }, 'GitHub')).to eq(
      'repositories.seo.title_without_language|language=|platform=GitHub|repository=app'
    )
    expect(
      host.call(:organization_profile_seo_description, { city: 'Warszawa' }, 'Acme Labs (acme)', 'GitHub')
    ).to eq(
      'organizations.seo.description|location=Warszawa|organization=Acme Labs (acme)|platform=GitHub'
    )
    expect(host.call(:organization_profile_seo_description, {}, 'Acme Labs (acme)', 'GitHub')).to eq(
      'organizations.seo.description_without_location|location=|organization=Acme Labs (acme)|platform=GitHub'
    )
    expect(
      host.call(
        :organization_repository_profile_seo_title,
        { full_name: 'acme/tool', name: 'tool', language: 'Go' },
        'GitHub'
      )
    ).to eq(
      'organization_repositories.seo.title|language=Go|platform=GitHub|repository=tool'
    )
    expect(host.call(:organization_repository_profile_seo_title, { full_name: 'acme/tool' }, 'GitHub')).to eq(
      'organization_repositories.seo.title_without_language|language=|platform=GitHub|repository=tool'
    )
  end

  it 'formats repository summary helpers', :aggregate_failures do
    summary = host.call(
      :repository_seo_summary,
      {
        language: 'Ruby',
        description: 'A fairly long repository description for Polish Open Source.',
        stargazers_count: 123
      }
    )

    expect(summary).to include('repositories.seo.summary_language|language=Ruby')
    expect(summary).to include('repositories.seo.summary_stars|stars=123')
    expect(host.call(:owner_display_name, 'Alice Example', 'alice')).to eq('Alice Example (alice)')
    expect(host.call(:owner_login_display_name, 'Alice Example', 'alice')).to eq('alice (Alice Example)')
    expect(host.call(:owner_display_name, 'alice', 'alice')).to eq('alice')
    expect(host.call(:repository_display_name, { full_name: 'alice/app' })).to eq('app')
    expect(host.call(:seo_excerpt, 'word ' * 40, limit: 20)).to end_with('...')
  end
end

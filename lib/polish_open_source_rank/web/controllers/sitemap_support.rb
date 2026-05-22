# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module SitemapSupport
        SITEMAP_RANKING_SEGMENTS = [%w[users top], %w[users trending], %w[users active],
                                    %w[repositories top], %w[repositories trending]].freeze

        private

        def render_robots_txt
          <<~TXT
            User-agent: *
            Allow: /

            Sitemap: #{full_url(app_path('/sitemap.xml'))}
          TXT
        end

        def render_sitemap
          urls = sitemap_entries.uniq.map do |entry|
            <<~XML
              <url>
                <loc>#{h entry.fetch(:loc)}</loc>
                <lastmod>#{h entry.fetch(:lastmod)}</lastmod>
              </url>
            XML
          end

          <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            #{urls.join}
            </urlset>
          XML
        end

        def sitemap_entries
          lastmod = Time.now.utc.strftime('%Y-%m-%d')
          static_paths = ['/', '/latest', '/about', '/editions']
          locale_paths = locale_variants(static_paths + ranking_paths + edition_paths + profile_paths)

          locale_paths.map do |path|
            { loc: full_url(app_path(path)), lastmod: lastmod }
          end
        end

        def ranking_paths
          latest_paths = SITEMAP_RANKING_SEGMENTS.map { |kind, metric| "/latest/#{kind}/#{metric}" }
          city_paths = Contexts::Ranking::Domain::LocationCatalog.city_slugs.flat_map do |slug|
            ["/locations/#{slug}", "/latest/locations/#{slug}"] + ranking_scope_paths("/latest/locations/#{slug}")
          end

          edition_period_slugs.each_with_object(latest_paths + city_paths) do |period_slug, paths|
            paths << "/#{period_slug}"
            paths.concat(Contexts::Ranking::Domain::LocationCatalog.city_slugs.map do |slug|
              "/#{period_slug}/locations/#{slug}"
            end)
            paths.concat(ranking_scope_paths("/#{period_slug}"))
            paths.concat(Contexts::Ranking::Domain::LocationCatalog.city_slugs.flat_map do |slug|
              ranking_scope_paths("/#{period_slug}/locations/#{slug}")
            end)
          end
        end

        def ranking_scope_paths(prefix)
          SITEMAP_RANKING_SEGMENTS.map { |kind, metric| "#{prefix}/#{kind}/#{metric}" }
        end

        def edition_paths
          years = list_editions.call&.years || []
          years.map { |year| "/editions/#{year}" }
        end

        def profile_paths
          users = profile_read_model.public_user_identities.map do |row|
            "/users/#{row.fetch(:platform)}/#{row.fetch(:login)}"
          end
          period = latest_period
          return users unless period

          page = show_rankings.call(scope: 'poland', period_start: period)
          repositories = page.repository_rankings.values.flatten.map do |row|
            platform = row.fetch(:platform, 'github')
            owner, name = row.fetch(:full_name).split('/', 2)
            "/repositories/#{platform}/#{owner}/#{name}"
          end

          users + repositories
        end

        def edition_period_slugs
          years = list_editions.call&.years || []
          years.flat_map do |year|
            list_editions.call(year: year).editions.map { |edition| edition.fetch(:period_start)[0, 7] }
          end
        end

        def locale_variants(paths)
          paths.flat_map do |path|
            [path, localized_public_path(path, locale: 'en')]
          end
        end
      end
    end
  end
end

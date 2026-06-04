# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module SitemapSupport
        SITEMAP_URL_LIMIT = 50_000

        private

        def render_robots_txt
          <<~TXT
            User-agent: *
            Disallow: /internal/
            Allow: /

            Sitemap: #{full_url(app_path('/sitemap.xml'))}
          TXT
        end

        def render_sitemap
          content_type 'application/xml'
          entries = unique_sitemap_entries
          return render_sitemap_index(entries) if entries.size > SITEMAP_URL_LIMIT

          render_sitemap_urlset(entries)
        end

        def render_sitemap_page(page)
          content_type 'application/xml'
          return not_found if page < 1

          entries = unique_sitemap_entries.each_slice(SITEMAP_URL_LIMIT).to_a.fetch(page - 1) { return not_found }
          render_sitemap_urlset(entries)
        end

        def render_sitemap_urlset(entries)
          urls = entries.map do |entry|
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

        def render_sitemap_index(entries)
          generated_on = Time.now.utc.strftime('%Y-%m-%d')
          sitemaps = entries.each_slice(SITEMAP_URL_LIMIT).with_index(1).map do |_chunk, page|
            <<~XML
              <sitemap>
                <loc>#{h full_url(app_path("/sitemaps/#{page}.xml"))}</loc>
                <lastmod>#{h generated_on}</lastmod>
              </sitemap>
            XML
          end

          <<~XML
            <?xml version="1.0" encoding="UTF-8"?>
            <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
            #{sitemaps.join}
            </sitemapindex>
          XML
        end

        def unique_sitemap_entries
          sitemap_entries.uniq
        end

        def sitemap_entries
          SitemapEntries.new(self, catalog: sitemap_catalog).call
        end
      end
    end
  end
end

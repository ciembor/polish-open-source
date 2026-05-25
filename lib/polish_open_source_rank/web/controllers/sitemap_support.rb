# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module SitemapSupport
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
          SitemapEntries.new(self).call
        end
      end
    end
  end
end

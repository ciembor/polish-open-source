# frozen_string_literal: true

module PolishGithubRank
  module Infrastructure
    class GitHubGateway
      STAR_ACCEPT = "application/vnd.github.star+json"
      PER_PAGE = 100
      SEARCH_PAGE_LIMIT = 10

      def initialize(client)
        @client = client
      end

      def search_users_by_location(term)
        query = %(type:user location:"#{term}")
        each_page("/search/users", { q: query }, limit: SEARCH_PAGE_LIMIT)
          .flat_map { |response| response.body.fetch("items", []) }
      end

      def user(login)
        client.get("/users/#{login}").body
      end

      def repositories_for(login)
        each_page(
          "/users/#{login}/repos",
          { type: "owner", sort: "full_name", direction: "asc" }
        ).flat_map(&:body)
      end

      def repository_stars_delta(full_name, period)
        owner, repo = full_name.split("/", 2)
        first_page = stargazers_page(owner, repo, 1)
        last_page = last_page_number(first_page.headers.fetch("link", nil)) || 1
        return count_stars(first_page.body, period) if last_page == 1

        count_stars_backwards(owner, repo, period, last_page)
      end

      def public_activity_count(login, period)
        count = 0
        each_page("/users/#{login}/events/public", {}) do |response|
          times = response.body.map { |event| Time.parse(event.fetch("created_at")) }
          count += times.count { |time| period.cover_time?(time) }
          :stop if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      end

      private

      attr_reader :client

      def each_page(path, params, limit: nil)
        return enum_for(:each_page, path, params, limit: limit) unless block_given?

        page = 1
        loop do
          response = client.get(path, params: params.merge(per_page: PER_PAGE, page: page))
          signal = yield response
          break unless next_page?(response.headers.fetch("link", nil))
          break if limit && page >= limit
          break if signal == :stop

          page += 1
        end
      end

      def stargazers_page(owner, repo, page)
        client.get(
          "/repos/#{owner}/#{repo}/stargazers",
          params: { per_page: PER_PAGE, page: page },
          accept: STAR_ACCEPT
        )
      end

      def count_stars_backwards(owner, repo, period, last_page)
        count = 0
        last_page.downto(1) do |page|
          times = stargazers_page(owner, repo, page).body.map { |star| Time.parse(star.fetch("starred_at")) }
          count += times.count { |time| period.cover_time?(time) }
          break if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      end

      def count_stars(stargazers, period)
        stargazers.count { |star| period.cover_time?(Time.parse(star.fetch("starred_at"))) }
      end

      def next_page?(link_header)
        link_header.to_s.include?('rel="next"')
      end

      def last_page_number(link_header)
        match = link_header.to_s.match(/[?&]page=(\d+)>; rel="last"/)
        match && match[1].to_i
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class GitHubGateway
      STAR_ACCEPT = 'application/vnd.github.star+json'
      PER_PAGE = 100
      SEARCH_PAGE_LIMIT = 10
      SourceCandidate = Contexts::Ranking::Domain::SourceCandidate
      SourceContributor = Contexts::Ranking::Domain::SourceContributor
      SourceRepository = Contexts::Ranking::Domain::SourceRepository

      def initialize(client)
        @client = client
      end

      def platform
        'github'
      end

      def search_users_by_location(term)
        query = %(type:user location:"#{term}")
        each_page('/search/users', { q: query }, limit: SEARCH_PAGE_LIMIT)
          .flat_map { |response| response.body.fetch('items', []).map { |user| candidate(user) } }
      end

      def supports_organizations?
        true
      end

      def search_organizations_by_location(term)
        query = %(type:org location:"#{term}")
        each_page('/search/users', { q: query }, limit: SEARCH_PAGE_LIMIT)
          .flat_map { |response| response.body.fetch('items', []).map { |organization| candidate(organization) } }
      end

      def user(login, _github_id = nil)
        profile(client.get("/users/#{login}").body)
      rescue GitHubClient::NotFound
        raise Contexts::Ranking::Application::SourceNotFound
      end

      def organization(login, _github_id = nil)
        profile(client.get("/orgs/#{login}").body)
      rescue GitHubClient::NotFound
        raise Contexts::Ranking::Application::SourceNotFound
      end

      def repositories_for(profile)
        login = profile.fetch(:login)
        each_page(
          "/users/#{login}/repos",
          { type: 'owner', sort: 'full_name', direction: 'asc' }
        ).flat_map { |response| response.body.map { |repository| repository(repository) } }
      end

      def repositories_for_organization(profile)
        login = profile.fetch(:login)
        each_page(
          "/orgs/#{login}/repos",
          { type: 'public', sort: 'full_name', direction: 'asc' }
        ).flat_map { |response| response.body.map { |repository| repository(repository) } }
      end

      def repository_stars_delta(repository, period)
        return 0 if repository.key?(:stars) && repository.fetch(:stars).zero?

        owner, repo = repository_coordinates(repository)
        first_page = stargazers_page(owner, repo, 1)
        last_page = last_page_number(first_page.headers.fetch('link', nil)) || 1
        return count_stars(first_page.body, period) if last_page == 1

        count_stars_backwards(owner, repo, period, last_page)
      rescue GitHubClient::Error => e
        raise unless [403, 451].include?(e.status)

        0
      end

      def public_activity_count(profile, period)
        login = profile.fetch(:login)
        count = 0
        each_page("/users/#{login}/events/public", {}) do |response|
          times = response.body.map { |event| Time.parse(event.fetch('created_at')) }
          count += times.count { |time| period.cover_time?(time) }
          :stop if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      end

      private

      attr_reader :client

      def candidate(user)
        SourceCandidate.new(source_id: user.fetch('id'), login: user.fetch('login'))
      end

      def profile(user)
        SourceContributor.new(
          source_id: user.fetch('id'),
          login: user.fetch('login'),
          name: user['name'],
          location: user['location'],
          email: user['email'],
          homepage: user['blog'],
          html_url: user.fetch('html_url'),
          avatar_url: user['avatar_url']
        )
      end

      def repository(repository)
        SourceRepository.new(
          source_id: repository.fetch('id'),
          name: repository.fetch('name'),
          full_name: repository.fetch('full_name'),
          description: repository['description'],
          html_url: repository.fetch('html_url'),
          homepage: repository['homepage'],
          language: repository['language'],
          fork: repository.fetch('fork'),
          archived: repository.fetch('archived'),
          stars: Integer(repository.fetch('stargazers_count'))
        )
      end

      def each_page(path, params, limit: nil)
        return enum_for(:each_page, path, params, limit: limit) unless block_given?

        page = 1
        loop do
          response = client.get(path, params: params.merge(per_page: PER_PAGE, page: page))
          signal = yield response
          break unless next_page?(response.headers.fetch('link', nil))
          break if page == limit
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

      def repository_coordinates(repository)
        full_name = repository.fetch(:full_name)
        match = full_name.match(%r{\A([^/]+)/([^/]+)\z})
        raise ArgumentError, "Invalid GitHub repository full_name: #{full_name.inspect}" unless match

        [match[1], match[2]]
      end

      def count_stars_backwards(owner, repo, period, last_page)
        count = 0
        last_page.downto(1) do |page|
          times = stargazers_page(owner, repo, page).body.map { |star| Time.parse(star.fetch('starred_at')) }
          count += times.count { |time| period.cover_time?(time) }
          break if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      end

      def count_stars(stargazers, period)
        stargazers.count { |star| period.cover_time?(Time.parse(star.fetch('starred_at'))) }
      end

      def next_page?(link_header)
        link_header.to_s.include?('rel="next"')
      end

      def last_page_number(link_header)
        match = link_header.to_s.match(/[?&]page=(\d+)>; rel="last"/)
        match && Integer(match[1])
      end
    end
  end
end

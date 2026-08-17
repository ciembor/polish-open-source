# frozen_string_literal: true

require 'json'

module PolishOpenSourceRank
  module Infrastructure
    class GitHubGateway
      PER_PAGE = 100
      SEARCH_PAGE_LIMIT = 10
      UNAVAILABLE_SEARCH_MESSAGES = [
        'The listed users cannot be searched either because the users do not exist ' \
        'or you do not have permission to view the users.',
        'The listed users and repositories cannot be searched either because the resources do not exist ' \
        'or you do not have permission to view them.'
      ].freeze
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
        each_repository_for(profile).to_a
      end

      def each_repository_for(profile)
        return enum_for(:each_repository_for, profile) unless block_given?

        login = profile.fetch(:login)
        each_page(
          "/users/#{login}/repos",
          { type: 'owner', sort: 'full_name', direction: 'asc' }
        ) do |response|
          response.body.each { |repository| yield repository(repository) }
        end
      end

      def repositories_for_organization(profile)
        each_repository_for_organization(profile).to_a
      end

      def each_repository_for_organization(profile)
        return enum_for(:each_repository_for_organization, profile) unless block_given?

        login = profile.fetch(:login)
        each_page(
          "/orgs/#{login}/repos",
          { type: 'public', sort: 'full_name', direction: 'asc' }
        ) do |response|
          response.body.each { |repository| yield repository(repository) }
        end
      end

      def repository_stars_delta(repository, period)
        repository_star_snapshot(repository, period).fetch(:monthly_stars_delta)
      end

      def repository_star_snapshot(repository, _period)
        observed_stars = repository_stars(repository)
        {
          stars: observed_stars,
          stargazers_count: observed_stars,
          monthly_stars_delta: 0
        }
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

      def merged_pull_requests_count(profile, period)
        login = profile.fetch(:login)
        search_merged_pull_requests_count(merged_pull_request_query(login, period))
      end

      def organization_merged_pull_requests_count(profile, period)
        login = profile.fetch(:login)
        search_merged_pull_requests_count(organization_merged_pull_request_query(login, period))
      end

      def organization_members_count(profile)
        response = client.get("/orgs/#{profile.fetch(:login)}/members", params: { per_page: 1, page: 1 })
        member_count(response)
      rescue GitHubClient::NotFound
        raise Contexts::Ranking::Application::SourceNotFound
      end

      private

      attr_reader :client

      def search_merged_pull_requests_count(query)
        response = client.get(
          '/search/issues',
          params: { q: query, per_page: 1, page: 1 }
        )
        Integer(response.body.fetch('total_count', 0))
      rescue GitHubClient::Error => e
        raise unless unavailable_search_resource?(e)

        0
      end

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

      def repository_stars(repository)
        return repository.stars if repository.respond_to?(:stars)

        Integer(repository.fetch(:stars))
      end

      def next_page?(link_header)
        link_header.to_s.include?('rel="next"')
      end

      def last_page_number(link_header)
        match = link_header.to_s.match(/[?&]page=(\d+)>; rel="last"/)
        match && Integer(match[1])
      end

      def merged_pull_request_query(login, period)
        [
          qualifier('author', login),
          'is:pr',
          'is:merged',
          'is:public',
          "-#{qualifier('user', login)}",
          "merged:#{period.start_date}..#{period.end_date - 1}"
        ].join(' ')
      end

      def organization_merged_pull_request_query(login, period)
        [
          qualifier('org', login),
          'is:pr',
          'is:merged',
          'is:public',
          "merged:#{period.start_date}..#{period.end_date - 1}"
        ].join(' ')
      end

      def qualifier(name, value)
        %(#{name}:#{quoted_search_value(value)})
      end

      def quoted_search_value(value)
        return value if value.match?(/\A[a-z0-9-]+\z/i)

        %("#{value.gsub('"', '\"')}")
      end

      def unavailable_search_resource?(error)
        return false unless error.status == 422

        parsed_body = JSON.parse(error.body.to_s)
        parsed_body.fetch('message', nil) == 'Validation Failed' && invalid_search_query?(parsed_body['errors'])
      rescue JSON::ParserError
        false
      end

      def invalid_search_query?(errors)
        Array(errors).any? { |entry| invalid_search_query_entry?(entry) }
      end

      def invalid_search_query_entry?(entry)
        entry['resource'] == 'Search' &&
          entry['field'] == 'q' &&
          entry['code'] == 'invalid' &&
          UNAVAILABLE_SEARCH_MESSAGES.include?(entry['message'])
      end

      def member_count(response)
        last_page = last_page_number(response.headers.fetch('link', nil))
        return last_page if last_page

        Array(response.body).length
      end
    end
  end
end

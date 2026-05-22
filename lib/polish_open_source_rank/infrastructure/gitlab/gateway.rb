# frozen_string_literal: true

module PolishOpenSourceRank
  module Infrastructure
    class GitLabGateway
      PER_PAGE = 100
      SEARCH_PAGE_LIMIT = 10
      SourceCandidate = Contexts::Ranking::Domain::SourceCandidate
      SourceContributor = Contexts::Ranking::Domain::SourceContributor
      SourceRepository = Contexts::Ranking::Domain::SourceRepository

      def initialize(client)
        @client = client
      end

      def platform
        'gitlab'
      end

      def supports_organizations?
        false
      end

      def search_users_by_location(term)
        each_page('/users', { search: term }, limit: SEARCH_PAGE_LIMIT)
          .flat_map { |response| response.body.map { |user| candidate(user) } }
      end

      def user(_login, gitlab_id)
        profile(client.get("/users/#{gitlab_id}").body)
      rescue GitLabClient::NotFound
        raise Contexts::Ranking::Application::SourceNotFound
      end

      def repositories_for(profile)
        each_page(
          "/users/#{profile.fetch(:source_id)}/projects",
          { simple: true, order_by: 'path', sort: 'asc' }
        ).flat_map { |response| response.body.map { |repository| repository(repository) } }
      end

      def repository_stars_delta(_repository, _period)
        0
      end

      def public_activity_count(profile, period)
        count = 0
        each_page("/users/#{profile.fetch(:source_id)}/events", {}) do |response|
          times = response.body.map { |event| Time.parse(event.fetch('created_at')) }
          count += times.count { |time| period.cover_time?(time) }
          :stop if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      rescue GitLabClient::NotFound
        0
      end

      private

      attr_reader :client

      def candidate(user)
        SourceCandidate.new(source_id: user.fetch('id'), login: user.fetch('username'))
      end

      def profile(user)
        SourceContributor.new(
          source_id: user.fetch('id'),
          login: user.fetch('username'),
          name: user['name'],
          location: user['location'],
          email: user['public_email'],
          homepage: user['website_url'],
          html_url: user.fetch('web_url'),
          avatar_url: user['avatar_url']
        )
      end

      def repository(repository)
        SourceRepository.new(
          source_id: repository.fetch('id'),
          name: repository.fetch('name'),
          full_name: repository.fetch('path_with_namespace'),
          description: repository['description'],
          html_url: repository.fetch('web_url'),
          homepage: repository['web_url'],
          language: repository['language'],
          fork: !repository['forked_from_project'].nil?,
          archived: repository.fetch('archived', false),
          stars: repository.fetch('star_count').to_i
        )
      end

      def each_page(path, params, limit: nil)
        return enum_for(:each_page, path, params, limit: limit) unless block_given?

        page = 1
        loop do
          response = client.get(path, params: params.merge(per_page: PER_PAGE, page: page))
          signal = yield response
          break unless next_page?(response.headers)
          break if limit && page >= limit
          break if signal == :stop

          page += 1
        end
      end

      def next_page?(headers)
        headers.fetch('x-next-page', '').to_s != ''
      end
    end
  end
end

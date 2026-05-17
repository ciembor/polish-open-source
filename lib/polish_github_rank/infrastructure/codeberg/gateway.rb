# frozen_string_literal: true

module PolishGithubRank
  module Infrastructure
    class CodebergGateway
      PER_PAGE = 50
      SEARCH_PAGE_LIMIT = 10

      def initialize(client)
        @client = client
      end

      def platform
        'codeberg'
      end

      def search_users_by_location(term)
        each_page('/users/search', { q: term }, limit: SEARCH_PAGE_LIMIT)
          .flat_map { |response| response.body.fetch('data', []).map { |user| candidate(user) } }
      end

      def user(login, _codeberg_id = nil)
        profile(client.get("/users/#{login}").body)
      rescue CodebergClient::NotFound
        raise Application::SourceNotFound
      end

      def repositories_for(profile)
        each_page(
          '/repos/search',
          { uid: profile.fetch(:source_id), sort: 'alpha', order: 'asc' }
        ).flat_map { |response| response.body.fetch('data', []).map { |repository| repository(repository) } }
      end

      def repository_stars_delta(_repository, _period)
        0
      end

      def public_activity_count(profile, period)
        count = 0
        each_page("/users/#{profile.fetch(:login)}/activities/feeds", { 'only-performed-by' => true }) do |response|
          times = response.body.map { |event| event_time(event) }.compact
          count += times.count { |time| period.cover_time?(time) }
          :stop if times.any? && times.all? { |time| time.to_date < period.start_date }
        end
        count
      rescue CodebergClient::NotFound
        0
      end

      private

      attr_reader :client

      def candidate(user)
        { source_id: user.fetch('id'), login: user.fetch('login') }
      end

      def profile(user)
        {
          source_id: user.fetch('id'),
          login: user.fetch('login'),
          name: user['full_name'],
          location: user['location'],
          email: user['email'],
          homepage: user['website'],
          html_url: user.fetch('html_url'),
          avatar_url: user['avatar_url']
        }
      end

      def repository(repository)
        {
          source_id: repository.fetch('id'),
          name: repository.fetch('name'),
          full_name: repository.fetch('full_name'),
          description: repository['description'],
          html_url: repository.fetch('html_url'),
          homepage: repository['website'],
          language: repository['language'],
          fork: repository.fetch('fork'),
          archived: repository.fetch('archived'),
          stars: repository.fetch('stars_count').to_i
        }
      end

      def each_page(path, params, limit: nil)
        return enum_for(:each_page, path, params, limit: limit) unless block_given?

        page = 1
        loop do
          response = client.get(path, params: params.merge(limit: PER_PAGE, page: page))
          signal = yield response
          break unless next_page?(response)
          break if limit && page >= limit
          break if signal == :stop

          page += 1
        end
      end

      def next_page?(response)
        page_items(response.body).length == PER_PAGE
      end

      def page_items(body)
        body.is_a?(Hash) ? body.fetch('data', []) : Array(body)
      end

      def event_time(event)
        raw_time = event['created_at'] || event['created']
        Time.parse(raw_time) if raw_time
      end
    end
  end
end

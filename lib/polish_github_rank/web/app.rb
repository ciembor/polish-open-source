# frozen_string_literal: true

require 'sinatra/base'

module PolishGithubRank
  module Web
    class App < Sinatra::Base
      set :public_folder, PolishGithubRank.root.join('app/public').to_s
      set :views, PolishGithubRank.root.join('app/views').to_s

      helpers do
        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def number(value)
          value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1 ').reverse
        end

        def scopes
          Domain::LocationCatalog.scopes
        end

        def city_path(slug)
          "/locations/#{slug}"
        end

        def canonical_url
          base_url = Configuration.load.public_base_url.delete_suffix('/')
          "#{base_url}#{@canonical_path || request.path_info}"
        end

        def structured_data
          JSON.pretty_generate(
            '@context' => 'https://schema.org',
            '@type' => 'Dataset',
            'name' => @title,
            'description' => @description,
            'url' => canonical_url
          )
        end
      end

      get '/' do
        render_rankings('poland')
      end

      get '/locations/:slug' do
        halt 404 unless Domain::LocationCatalog.city_slugs.include?(params.fetch('slug'))

        render_rankings(params.fetch('slug'))
      end

      get '/healthz' do
        'ok'
      end

      not_found do
        status 404
        @title = 'Ranking nie znaleziony'
        @description = 'Nie znaleziono rankingu dla podanej lokalizacji.'
        erb :not_found
      end

      private

      def render_rankings(scope)
        @scope = scope_data(scope)
        @period = store.latest_period
        @user_rankings = rankings_or_empty(@period) { store.user_rankings(scope, period_start: @period) }
        @repository_rankings = rankings_or_empty(@period) { store.repository_rankings(scope, period_start: @period) }
        @title = "#{@scope.fetch(:name)} GitHub ranking"
        @description = 'Top i trending publiczni użytkownicy oraz repozytoria GitHuba ' \
                       "dla lokalizacji #{@scope.fetch(:name)}."
        @canonical_path = scope == 'poland' ? '/' : city_path(scope)
        erb :rankings
      end

      def store
        @store ||= begin
          configuration = Configuration.load
          Infrastructure::SQLiteStore.new(configuration.database_path).migrate!
        end
      end

      def rankings_or_empty(period)
        return empty_rankings unless period

        yield
      end

      def empty_rankings
        { top: [], trending: [], active: [] }
      end

      def scope_data(scope)
        return { slug: 'poland', name: 'Polska', type: :country } if scope == 'poland'

        Domain::LocationCatalog::CITY_BY_SLUG.fetch(scope)
      end
    end
  end
end

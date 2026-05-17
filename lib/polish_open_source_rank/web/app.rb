# frozen_string_literal: true

require 'sinatra/base'

module PolishOpenSourceRank
  module Web
    class App < Sinatra::Base
      set :public_folder, PolishOpenSourceRank.root.join('app/public').to_s
      set :views, PolishOpenSourceRank.root.join('app/views').to_s

      RANKING_DETAIL_SEGMENTS = '(users|repositories)/(top|trending|active)'
      SUPPORTED_LOCALES = %w[en pl].freeze
      DEFAULT_LOCALE = 'en'
      TRANSLATIONS = {
        'en' => {
          'footer.data_source' => 'Data comes from the public APIs of GitHub, GitLab and Codeberg ' \
                                  'and is refreshed monthly.',
          'nav.about' => 'About',
          'nav.country' => 'Poland',
          'nav.editions' => 'Editions',
          'nav.language' => 'Language',
          'nav.locations' => 'Location rankings',
          'nav.more_cities' => 'More cities'
        },
        'pl' => {
          'footer.data_source' => 'Dane pochodzą z publicznych API GitHuba, GitLaba i Codeberga ' \
                                  'i są odświeżane miesięcznie.',
          'nav.about' => 'About',
          'nav.country' => 'Polska',
          'nav.editions' => 'Edycje',
          'nav.language' => 'Język',
          'nav.locations' => 'Rankingi lokalizacji',
          'nav.more_cities' => 'Więcej miast'
        }
      }.freeze

      before do
        @locale = selected_locale
        response.set_cookie(
          'locale',
          value: @locale,
          path: locale_cookie_path,
          max_age: 31_536_000,
          same_site: :lax
        )
      end

      helpers do
        def h(value)
          Rack::Utils.escape_html(value.to_s)
        end

        def number(value)
          value.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse
        end

        def t(key)
          TRANSLATIONS.fetch(current_locale).fetch(key)
        end

        def current_locale
          @locale || DEFAULT_LOCALE
        end

        def current_locale?(locale)
          current_locale == locale
        end

        def locale_path(locale)
          query = Rack::Utils.parse_nested_query(request.query_string)
          query.delete('lang')
          query['lang'] = locale
          "#{app_path(request.path_info)}?#{Rack::Utils.build_query(query)}"
        end

        def platform_name(platform)
          {
            'codeberg' => 'Codeberg',
            'gitlab' => 'GitLab',
            'github' => 'GitHub'
          }.fetch(platform, 'GitHub')
        end

        def platform_icon_path(platform)
          {
            'codeberg' => '/icons/codeberg.svg',
            'gitlab' => '/icons/gitlab.svg',
            'github' => '/icons/github.svg'
          }.fetch(platform, '/icons/github.svg')
        end

        def scopes
          Domain::LocationCatalog.scopes
        end

        def primary_city_scopes
          Domain::LocationCatalog.primary_city_scopes
        end

        def secondary_city_scopes
          Domain::LocationCatalog.secondary_city_scopes
        end

        def city_path(slug, period_slug: @period_slug)
          "#{period_base_path(period_slug)}/locations/#{slug}"
        end

        def scope_path(scope, period_slug: @period_slug)
          return period_base_path(period_slug) if scope.fetch(:slug) == 'poland'

          city_path(scope.fetch(:slug), period_slug: period_slug)
        end

        def ranking_path(kind, metric, period_slug: @period_slug, scope_slug: @scope.fetch(:slug))
          "#{scope_path({ slug: scope_slug }, period_slug: period_slug)}/#{kind}/#{metric}"
        end

        def period_base_path(period_slug)
          return '/latest' if period_slug.nil? || period_slug == 'latest'

          "/#{period_slug}"
        end

        def app_path(path)
          "#{configuration.app_base_path}#{path}"
        end

        def editions_path(year = nil)
          year ? "/editions/#{year}" : '/editions'
        end

        def period_label(period_start)
          date = Date.parse(period_start)
          months = %w[styczeń luty marzec kwiecień maj czerwiec lipiec sierpień wrzesień październik listopad grudzień]
          "#{months.fetch(date.month - 1)} #{date.year}"
        end

        def canonical_url
          base_url = configuration.public_base_url.delete_suffix('/')
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

        def configuration
          @configuration ||= Configuration.load
        end
      end

      get '/' do
        render_rankings('latest', 'poland')
      end

      get '/latest' do
        render_rankings('latest', 'poland')
      end

      get '/about' do
        @title = 'O Polish Open Source Rank'
        @description = 'Misja, zasady generowania rankingów i wspierane platformy Polish Open Source Rank.'
        @canonical_path = '/about'
        erb :about
      end

      get '/editions' do
        render_editions
      end

      get %r{/editions/(\d{4})} do |year|
        render_editions(year)
      end

      get '/latest/locations/:slug' do
        render_city('latest', params.fetch('slug'))
      end

      get %r{/latest/#{RANKING_DETAIL_SEGMENTS}} do |kind, metric|
        render_ranking_detail('latest', 'poland', kind, metric)
      end

      get %r{/latest/locations/([^/]+)/#{RANKING_DETAIL_SEGMENTS}} do |slug, kind, metric|
        render_city_ranking_detail('latest', slug, kind, metric)
      end

      get %r{/(\d{4}-\d{2})/#{RANKING_DETAIL_SEGMENTS}} do |period_slug, kind, metric|
        render_ranking_detail(period_slug, 'poland', kind, metric)
      end

      get %r{/(\d{4}-\d{2})/locations/([^/]+)/#{RANKING_DETAIL_SEGMENTS}} do |period_slug, slug, kind, metric|
        render_city_ranking_detail(period_slug, slug, kind, metric)
      end

      get %r{/(\d{4}-\d{2})} do |period_slug|
        render_rankings(period_slug, 'poland')
      end

      get %r{/(\d{4}-\d{2})/locations/([^/]+)} do |period_slug, slug|
        render_city(period_slug, slug)
      end

      get '/locations/:slug' do
        render_city('latest', params.fetch('slug'))
      end

      get '/healthz' do
        'ok'
      end

      get '/internal/jobs' do
        headers 'Cache-Control' => 'no-store', 'X-Robots-Tag' => 'noindex'
        content_type :json
        JSON.pretty_generate(store.job_progress)
      end

      not_found do
        status 404
        @title = 'Ranking nie znaleziony'
        @description = 'Nie znaleziono rankingu dla podanej lokalizacji.'
        erb :not_found
      end

      private

      def selected_locale
        explicit_locale || cookie_locale || accepted_locale || DEFAULT_LOCALE
      end

      def explicit_locale
        locale = params['lang']
        SUPPORTED_LOCALES.include?(locale) ? locale : nil
      end

      def cookie_locale
        locale = request.cookies['locale']
        SUPPORTED_LOCALES.include?(locale) ? locale : nil
      end

      def accepted_locale
        request.env.fetch('HTTP_ACCEPT_LANGUAGE', '').split(',').filter_map do |language|
          locale = language.split(';', 2).first.to_s.strip.split('-', 2).first
          locale if SUPPORTED_LOCALES.include?(locale)
        end.first
      end

      def locale_cookie_path
        configuration.app_base_path.empty? ? '/' : configuration.app_base_path
      end

      def render_city(period_slug, slug)
        halt 404 unless Domain::LocationCatalog.city_slugs.include?(slug)

        render_rankings(period_slug, slug)
      end

      def render_city_ranking_detail(period_slug, slug, kind, metric)
        halt 404 unless Domain::LocationCatalog.city_slugs.include?(slug)

        render_ranking_detail(period_slug, slug, kind, metric)
      end

      def render_rankings(period_slug, scope)
        @scope = scope_data(scope)
        @period_slug = period_slug
        @period = period_for(period_slug)
        @user_rankings = rankings_or_empty(@period) { store.user_rankings(scope, period_start: @period) }
        @repository_rankings = rankings_or_empty(@period) { store.repository_rankings(scope, period_start: @period) }
        @title = "#{@scope.fetch(:name)} open-source ranking"
        @description = 'Top i trending publiczni użytkownicy oraz repozytoria platform kodu ' \
                       "dla lokalizacji #{@scope.fetch(:name)}."
        @canonical_path = scope == 'poland' ? period_base_path(period_slug) : city_path(scope, period_slug: period_slug)
        erb :rankings
      end

      def render_editions(year = nil)
        @years = store.edition_years.map { |row| row.fetch(:year) }
        @year = selected_edition_year(year)
        @editions = @year ? store.monthly_editions(@year) : []
        @newer_year = adjacent_edition_year(@year, -1)
        @older_year = adjacent_edition_year(@year, 1)
        @title = year ? "Edycje #{year}" : 'Edycje'
        @description = 'Archiwum miesięcznych rankingów z top projektami, użytkownikami według gwiazdek i aktywności.'
        @canonical_path = year ? editions_path(year) : editions_path
        erb :editions
      end

      def selected_edition_year(year)
        halt 404 if year && !@years.include?(year)

        year || @years.first
      end

      def adjacent_edition_year(year, offset)
        index = @years.index(year)
        return unless index

        adjacent_index = index + offset
        return if adjacent_index.negative?

        @years[adjacent_index]
      end

      def render_ranking_detail(period_slug, scope, kind, metric)
        halt 404 unless ranking_metric?(kind, metric)

        @scope = scope_data(scope)
        @period_slug = period_slug
        @period = period_for(period_slug)
        @kind = kind
        @metric = metric
        @ranking = ranking_for(scope, kind, metric, @period)
        @title = "#{@scope.fetch(:name)} #{ranking_title(kind, metric)}"
        @description = "#{ranking_title(kind, metric)} dla lokalizacji #{@scope.fetch(:name)}."
        @canonical_path = ranking_path(kind, metric, period_slug: period_slug, scope_slug: scope)
        erb :ranking_detail
      end

      def period_for(period_slug)
        return store.latest_period if period_slug == 'latest'

        halt 404 unless period_slug.match?(/\A\d{4}-\d{2}\z/)

        period_start = Application::MonthPeriod.parse(period_slug).start_date.to_s
        store.recorded_period?(period_start) ? period_start : halt(404)
      rescue Date::Error
        halt 404
      end

      def store
        @store ||= Infrastructure::SQLiteStore.new(configuration.database_path).migrate!
      end

      def rankings_or_empty(period)
        return empty_rankings unless period

        yield
      end

      def empty_rankings
        { top: [], trending: [], active: [] }
      end

      def ranking_for(scope, kind, metric, period)
        return [] unless period

        rankings = if kind == 'users'
                     store.user_rankings(scope, period_start: period)
                   else
                     store.repository_rankings(scope, period_start: period)
                   end
        rankings.fetch(metric.to_sym)
      end

      def ranking_metric?(kind, metric)
        return %w[top trending active].include?(metric) if kind == 'users'

        kind == 'repositories' && %w[top trending].include?(metric)
      end

      def ranking_title(kind, metric)
        {
          %w[users top] => 'Top 100 użytkowników według gwiazdek',
          %w[users trending] => 'Top 100 trendujących użytkowników',
          %w[users active] => 'Top 100 aktywnych użytkowników',
          %w[repositories top] => 'Top 100 repozytoriów według gwiazdek',
          %w[repositories trending] => 'Top 100 trendujących repozytoriów'
        }.fetch([kind, metric])
      end

      def ranking_metric_column(kind, metric)
        {
          %w[users top] => :total_stars,
          %w[users trending] => :monthly_stars_delta,
          %w[users active] => :public_activity_count,
          %w[repositories top] => :stargazers_count,
          %w[repositories trending] => :monthly_stars_delta
        }.fetch([kind, metric])
      end

      def ranking_metric_label(kind, metric)
        return 'Zdarzeń' if kind == 'users' && metric == 'active'
        return 'Nowe gwiazdki' if metric == 'trending'

        'Gwiazdek'
      end

      def scope_data(scope)
        return { slug: 'poland', name: 'Polska', type: :country } if scope == 'poland'

        Domain::LocationCatalog::CITY_BY_SLUG.fetch(scope)
      end
    end
  end
end

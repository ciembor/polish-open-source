# frozen_string_literal: true

require 'sinatra/base'

require_relative 'localization/locale_selector'
require_relative 'localization/translation_catalog'
require_relative 'presentation/platform_catalog'
require_relative 'presentation/ranking_catalog'
require_relative 'presentation/view_helpers'

module PolishOpenSourceRank
  module Web
    class App < Sinatra::Base
      ENV['TZ'] = 'Europe/Warsaw'

      set :public_folder, PolishOpenSourceRank.root.join('app/public').to_s
      set :views, PolishOpenSourceRank.root.join('app/views').to_s

      RANKING_DETAIL_SEGMENTS = '(users|repositories)/(top|trending|active)'
      SUPPORTED_LOCALES = %w[en pl].freeze
      DEFAULT_LOCALE = 'en'
      set :default_locale, DEFAULT_LOCALE
      set :localized_text,
          Localization::TranslationCatalog.load(root: PolishOpenSourceRank.root, locales: SUPPORTED_LOCALES)
      set :locale_selector, Localization::LocaleSelector.new(supported: SUPPORTED_LOCALES, default: DEFAULT_LOCALE)
      set :platform_catalog, Presentation::PlatformCatalog.new
      set :ranking_catalog, Presentation::RankingCatalog.new
      helpers Presentation::ViewHelpers

      before do
        @locale = settings.locale_selector.select(
          params: params,
          cookies: request.cookies,
          accept_language: request.env.fetch('HTTP_ACCEPT_LANGUAGE', nil)
        )
        response.set_cookie(
          'locale',
          value: @locale,
          path: locale_cookie_path,
          max_age: 31_536_000,
          same_site: :lax
        )
      end

      get '/' do
        render_rankings('latest', 'poland')
      end

      get '/latest' do
        render_rankings('latest', 'poland')
      end

      get '/about' do
        @title = t('about.title')
        @description = t('about.seo.description')
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
        @robots = 'noindex,nofollow'
        @refresh_seconds = 15
        @progress = store.job_progress
        @title = 'Job monitor'
        @description = 'Internal monthly ranking job monitor.'
        @canonical_path = '/internal/jobs'
        erb :job_monitor
      end

      not_found do
        status 404
        @title = t('not_found.title')
        @description = t('not_found.description')
        erb :not_found
      end

      private

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
        @title = "#{scope_name(@scope)} open-source ranking"
        @description = t('rankings.seo.description', scope: scope_name(@scope))
        @canonical_path = scope == 'poland' ? period_base_path(period_slug) : city_path(scope, period_slug: period_slug)
        erb :rankings
      end

      def render_editions(year = nil)
        @years = store.edition_years.map { |row| row.fetch(:year) }
        @year = selected_edition_year(year)
        @editions = @year ? store.monthly_editions(@year) : []
        @newer_year = adjacent_edition_year(@year, -1)
        @older_year = adjacent_edition_year(@year, 1)
        @title = year ? "#{t('editions.title')} #{year}" : t('editions.title')
        @description = t('editions.seo.description')
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
        @title = "#{scope_name(@scope)} #{ranking_title(kind, metric)}"
        @description = "#{ranking_title(kind, metric)} - #{scope_name(@scope)}."
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
        settings.ranking_catalog.include?(kind, metric)
      end

      def ranking_title(kind, metric)
        t(settings.ranking_catalog.descriptor(kind, metric).title_key)
      end

      def ranking_metric_column(kind, metric)
        settings.ranking_catalog.descriptor(kind, metric).column
      end

      def ranking_metric_label(kind, metric)
        t(settings.ranking_catalog.descriptor(kind, metric).label_key)
      end

      def chart_context(points, value_key, platforms, carry_forward: false, width: 720, height: 180)
        minutes = points.map { |point| point.fetch(:minute) }.uniq.sort
        max_value = points.map { |point| point.fetch(value_key).to_i }.max.to_i
        {
          points: points,
          value_key: value_key,
          platforms: platforms,
          minutes: minutes,
          max_value: max_value,
          carry_forward: carry_forward,
          width: width,
          height: height
        }
      end

      def chart_axis_values(context)
        max_value = context.fetch(:max_value).to_i
        [max_value, (max_value / 2.0).round, 0]
      end

      def chart_time_ticks(context)
        minutes = context.fetch(:minutes)
        return [] if minutes.empty?

        last_index = minutes.length - 1
        [0, minutes.length / 2, last_index].uniq.map do |index|
          x = minutes.one? ? 0 : (index.to_f / (minutes.length - 1) * context.fetch(:width))
          anchor = index == last_index ? 'end' : 'start'
          { label: format_monitor_time(minutes.fetch(index)), x: x.round(1), anchor: anchor }
        end
      end

      def chart_polyline(context, platform)
        minutes = context.fetch(:minutes)
        return '' if minutes.empty?

        max_value = context.fetch(:max_value)
        return '' if max_value.zero?

        values = chart_values(context, platform)
        minutes.each_with_index.map do |_minute, index|
          x = minutes.one? ? 0 : (index.to_f / (minutes.length - 1) * context.fetch(:width))
          y = context.fetch(:height) - (values.fetch(index).to_f / max_value * context.fetch(:height))
          "#{x.round(1)},#{y.round(1)}"
        end.join(' ')
      end

      def chart_values(context, platform)
        rows = context.fetch(:points).select { |point| point.fetch(:platform) == platform }
        value_by_minute = rows.to_h { |point| [point.fetch(:minute), point.fetch(context.fetch(:value_key)).to_i] }
        current = 0
        context.fetch(:minutes).map do |minute|
          current = value_by_minute.fetch(minute, current)
          context.fetch(:carry_forward) ? current : value_by_minute.fetch(minute, 0)
        end
      end

      def format_monitor_time(value)
        return 'n/a' unless value

        Time.parse(value).localtime.strftime('%H:%M:%S %Z')
      end

      def scope_data(scope)
        return { slug: 'poland', name: 'Polska', type: :country } if scope == 'poland'

        Domain::LocationCatalog::CITY_BY_SLUG.fetch(scope)
      end
    end
  end
end

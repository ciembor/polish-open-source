# frozen_string_literal: true

require 'sinatra/base'
require 'securerandom'

require_relative 'localization/locale_selector'
require_relative 'localization/translation_catalog'
require_relative 'presentation/badge_helpers'
require_relative 'presentation/badge_renderer'
require_relative 'presentation/platform_catalog'
require_relative 'presentation/ranking_catalog'
require_relative 'presentation/view_helpers'

module PolishOpenSourceRank
  module Web
    # rubocop:disable Metrics/ClassLength
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
      set :badge_renderer, Presentation::BadgeRenderer.new
      set :platform_catalog, Presentation::PlatformCatalog.new
      set :ranking_catalog, Presentation::RankingCatalog.new
      set :github_oauth_client, nil
      set :discord_oauth_client, nil
      set :discord_gateway, nil
      set :discord_role_map, Auth::DiscordRoleMap.new
      use Rack::Session::Cookie,
          key: 'polish_open_source_rank.session',
          path: '/',
          same_site: :lax,
          secret: Configuration.load.session_secret
      helpers Presentation::BadgeHelpers
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

      get '/auth/github' do
        session[:github_oauth_state] = SecureRandom.hex(24)
        redirect github_oauth_client.authorize_url(
          state: session.fetch(:github_oauth_state),
          redirect_uri: oauth_callback_url('/auth/github/callback')
        )
      end

      get '/auth/github/callback' do
        halt 400 unless secure_oauth_state?(:github_oauth_state)

        access_token = github_oauth_client.exchange_code(
          code: params.fetch('code'),
          redirect_uri: oauth_callback_url('/auth/github/callback')
        )
        github_user = github_oauth_client.user(access_token)
        profile = ranked_github_profile(github_user.fetch('login'))
        unless profile
          session[:current_user] = nil
          session[:unranked_github_login] = github_user.fetch('login')
          redirect app_path('/auth/unranked')
        end

        session[:current_user] = {
          platform: 'github',
          login: profile.fetch(:login),
          github_id: profile.fetch(:github_id)
        }
        redirect app_path(user_profile_path(profile))
      end

      get '/auth/discord' do
        redirect app_path('/auth/github') unless current_user

        session[:discord_oauth_state] = SecureRandom.hex(24)
        redirect discord_oauth_client.authorize_url(
          state: session.fetch(:discord_oauth_state),
          redirect_uri: oauth_callback_url('/auth/discord/callback')
        )
      end

      get '/auth/discord/callback' do
        redirect app_path('/auth/github') unless current_user
        halt 400 unless secure_oauth_state?(:discord_oauth_state)

        token = discord_oauth_client.exchange_code(
          code: params.fetch('code'),
          redirect_uri: oauth_callback_url('/auth/discord/callback')
        )
        discord_user = discord_oauth_client.user(token.fetch('access_token'))
        sync_discord_member(discord_user, token.fetch('access_token'))
        redirect app_path(user_profile_path(current_user))
      end

      get '/auth/unranked' do
        @title = t('auth.unranked.title')
        @description = t('auth.unranked.description')
        @canonical_path = '/auth/unranked'
        erb :auth_unranked
      end

      post '/logout' do
        session.clear
        redirect app_path('/latest')
      end

      get '/users/:platform/:login' do
        render_user_profile(params.fetch('platform'), params.fetch('login'))
      end

      get '/repositories/:platform/:owner/:name' do
        render_repository_profile(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
      end

      get '/badges/users/:platform/:login.svg' do
        render_user_badge(params.fetch('platform'), params.fetch('login'))
      end

      get '/badges/repositories/:platform/:owner/:name.svg' do
        render_repository_badge(params.fetch('platform'), params.fetch('owner'), params.fetch('name'))
      end

      get '/badges/repositories/:owner/:name.svg' do
        render_repository_badge('github', params.fetch('owner'), params.fetch('name'))
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

      def render_user_profile(platform, login)
        @period_slug = 'latest'
        @period = store.latest_period
        @profile = store.user_profile(platform, login, period_start: @period)
        halt 404 unless @profile

        @repositories = @profile.fetch(:repositories)
        display_name = @profile[:name].to_s.empty? ? @profile.fetch(:login) : @profile[:name]
        source_name = platform_name(@profile.fetch(:platform))
        @title = "#{display_name} - #{source_name} profile"
        @description = t('users.seo.description', user: display_name, platform: source_name)
        @canonical_path = user_profile_path(@profile)
        @discord_panel = discord_panel(@profile) if own_profile?(@profile) && @profile[:period_start]
        erb :user_profile
      end

      def render_repository_profile(platform, owner, name)
        @period_slug = 'latest'
        @period = store.latest_period
        @repository = store.repository_profile(platform, owner, name, period_start: @period)
        halt 404 unless @repository

        source_name = platform_name(@repository.fetch(:platform))
        @title = "#{@repository.fetch(:full_name)} - #{source_name} project"
        @description = t(
          'repositories.seo.description',
          repository: @repository.fetch(:full_name),
          platform: source_name
        )
        @canonical_path = repository_profile_path(@repository)
        erb :repository_profile
      end

      def render_repository_badge(platform, owner, name)
        repository = store.repository_profile(platform, owner, name, period_start: store.latest_period)
        halt 404 unless repository

        content_type 'image/svg+xml'
        headers 'Cache-Control' => 'public, max-age=3600'
        settings.badge_renderer.svg(repository.fetch(:polish_repo_badge), home_url: app_home_url)
      end

      def ranked_github_profile(login)
        profile = store.user_profile('github', login, period_start: store.latest_period)
        profile if profile && profile[:period_start]
      end

      def current_user
        session[:current_user]&.transform_keys(&:to_sym)
      end

      def own_profile?(profile)
        current_user &&
          current_user.fetch(:platform) == profile.fetch(:platform) &&
          current_user.fetch(:github_id).to_i == profile.fetch(:github_id).to_i
      end

      def discord_panel(profile)
        invite = current_discord_invite(profile)
        {
          invite: invite,
          access: store.discord_access(profile.fetch(:platform), profile.fetch(:github_id), period_start: @period)
        }
      rescue Auth::DiscordGateway::Error
        {
          invite: nil,
          access: store.discord_access(profile.fetch(:platform), profile.fetch(:github_id), period_start: @period),
          error: true
        }
      end

      def current_discord_invite(profile)
        existing = store.discord_invite(profile.fetch(:platform), profile.fetch(:github_id))
        return existing if existing && discord_gateway.invite_available?(existing.fetch(:code))

        invite = discord_gateway.create_invite(channel_id: configuration.discord_invite_channel_id)
        store.record_discord_invite(
          platform: profile.fetch(:platform),
          user_github_id: profile.fetch(:github_id),
          code: invite.fetch(:code),
          url: invite.fetch(:url)
        )
        invite
      end

      def sync_discord_member(discord_user, access_token)
        profile = ranked_github_profile(current_user.fetch(:login))
        halt 404 unless profile

        store.upsert_discord_connection(
          platform: profile.fetch(:platform),
          user_github_id: profile.fetch(:github_id),
          discord_user_id: discord_user.fetch('id'),
          discord_username: discord_user['global_name'] || discord_user.fetch('username')
        )
        access = store.discord_access(
          profile.fetch(:platform),
          profile.fetch(:github_id),
          period_start: store.latest_period
        )
        discord_gateway.sync_member(
          discord_user_id: discord_user.fetch('id'),
          access_token: access_token,
          github_login: profile.fetch(:login),
          desired_role_ids: discord_role_map.role_ids(access.fetch(:role_keys)),
          managed_role_ids: discord_role_map.managed_role_ids
        )
      end

      def secure_oauth_state?(session_key)
        expected = session.delete(session_key)
        given = params.fetch('state', nil)
        expected && given && expected.bytesize == given.bytesize && Rack::Utils.secure_compare(expected, given)
      end

      def oauth_callback_url(path)
        "#{configuration.public_base_url.delete_suffix('/')}#{path}"
      end

      def github_oauth_client
        settings.github_oauth_client || Auth::GitHubOAuthClient.new(configuration)
      end

      def discord_oauth_client
        settings.discord_oauth_client || Auth::DiscordOAuthClient.new(configuration)
      end

      def discord_gateway
        settings.discord_gateway || Auth::DiscordGateway.new(configuration)
      end

      def discord_role_map
        settings.discord_role_map
      end

      def render_user_badge(platform, login)
        user = store.user_profile(platform, login, period_start: store.latest_period)
        halt 404 unless user

        content_type 'image/svg+xml'
        headers 'Cache-Control' => 'public, max-age=3600'
        settings.badge_renderer.svg(user.fetch(:elite_badge), home_url: app_home_url)
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
    # rubocop:enable Metrics/ClassLength
  end
end

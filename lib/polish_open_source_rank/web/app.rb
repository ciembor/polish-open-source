# frozen_string_literal: true

require 'sinatra/base'
require 'securerandom'
require 'digest'

require_relative 'localization/locale_selector'
require_relative 'localization/translation_catalog'
require_relative 'presentation/badge_helpers'
require_relative 'presentation/badge_renderer'
require_relative 'presentation/platform_catalog'
require_relative 'presentation/ranking_catalog'
require_relative 'presentation/view_helpers'
require_relative 'http_cache'

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
      set :static_cache_control, [:public, :immutable, { max_age: 31_536_000 }]
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
      helpers HttpCache

      before do
        no_store! if auth_path?
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
        public_html_cache!('about')
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
        redirect discord_channel_url || app_path(user_profile_path(current_user))
      end

      get '/auth/unranked' do
        no_store!
        @title = t('auth.unranked.title')
        @description = t('auth.unranked.description')
        @canonical_path = '/auth/unranked'
        erb :auth_unranked
      end

      post '/logout' do
        no_store!
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
        headers 'Cache-Control' => 'no-store'
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

      def auth_path?
        request.path_info.start_with?('/auth/') || request.path_info == '/auth/github' ||
          request.path_info == '/auth/discord' || request.path_info == '/logout'
      end

      def public_cache_revision(period)
        store.public_cache_revision(period) || 'empty'
      end

      def latest_public_cache_key
        period = store.latest_period
        "#{period}:#{public_cache_revision(period)}"
      end

      def html_revision
        files_revision(
          'app/views/layout.erb',
          'app/views/about.erb',
          'app/views/editions.erb',
          'app/views/ranking_detail.erb',
          'app/views/rankings.erb',
          'app/views/repository_profile.erb',
          'app/views/user_profile.erb',
          'app/public/css/application.css',
          "config/locales/#{current_locale}.yml"
        )
      end

      def files_revision(*relative_paths)
        relative_paths.map { |path| PolishOpenSourceRank.root.join(path).mtime.to_i }.max
      end

      def locale_cookie_path
        configuration.app_base_path.empty? ? '/' : configuration.app_base_path
      end

      def asset_path(path)
        public_path = PolishOpenSourceRank.root.join('app/public', path.delete_prefix('/'))
        version = public_path.file? ? public_path.mtime.to_i : Time.now.to_i
        app_path("#{path}?v=#{version}")
      end

      def render_city(period_slug, slug)
        halt 404 unless Contexts::Ranking::Domain::LocationCatalog.city_slugs.include?(slug)

        render_rankings(period_slug, slug)
      end

      def render_city_ranking_detail(period_slug, slug, kind, metric)
        halt 404 unless Contexts::Ranking::Domain::LocationCatalog.city_slugs.include?(slug)

        render_ranking_detail(period_slug, slug, kind, metric)
      end

      def render_rankings(period_slug, scope)
        @scope = scope_data(scope)
        @period_slug = period_slug
        @period = period_for(period_slug)
        public_html_cache!('rankings', period_slug, scope, @period, public_cache_revision(@period))
        page = show_rankings.call(scope: scope, period_start: @period)
        @user_rankings = page.user_rankings
        @repository_rankings = page.repository_rankings
        @title = "#{scope_name(@scope)} open-source ranking"
        @description = t('rankings.seo.description', scope: scope_name(@scope))
        @canonical_path = scope == 'poland' ? period_base_path(period_slug) : city_path(scope, period_slug: period_slug)
        erb :rankings
      end

      def render_editions(year = nil)
        page = list_editions.call(year: year)
        halt 404 unless page

        @years = page.years
        @year = page.year
        public_html_cache!('editions', @year || 'index', latest_public_cache_key)
        @editions = page.editions
        @newer_year = page.newer_year
        @older_year = page.older_year
        @title = year ? "#{t('editions.title')} #{year}" : t('editions.title')
        @description = t('editions.seo.description')
        @canonical_path = year ? editions_path(year) : editions_path
        erb :editions
      end

      def render_user_profile(platform, login)
        @period_slug = 'latest'
        @period = store.latest_period
        @profile = show_user_profile.call(platform: platform, login: login, period_start: @period)
        halt 404 unless @profile
        profile_cache!(@profile)

        @repositories = @profile.fetch(:repositories)
        display_name = @profile[:name].to_s.empty? ? @profile.fetch(:login) : @profile[:name]
        source_name = platform_name(@profile.fetch(:platform))
        @title = "#{display_name} - #{source_name} profile"
        @description = t('users.seo.description', user: display_name, platform: source_name)
        @canonical_path = user_profile_path(@profile)
        @discord_panel = show_discord_panel_for(@profile) if own_profile?(@profile) && @profile[:period_start]
        @show_profile_badges = own_profile?(@profile)
        erb :user_profile
      end

      def render_repository_profile(platform, owner, name)
        @period_slug = 'latest'
        @period = store.latest_period
        @repository = show_repository_profile.call(platform: platform, owner: owner, name: name, period_start: @period)
        halt 404 unless @repository
        repository_profile_cache!(@repository)

        source_name = platform_name(@repository.fetch(:platform))
        @title = "#{@repository.fetch(:full_name)} - #{source_name} project"
        @description = t(
          'repositories.seo.description',
          repository: @repository.fetch(:full_name),
          platform: source_name
        )
        @canonical_path = repository_profile_path(@repository)
        @show_repository_badge = own_repository?(@repository)
        erb :repository_profile
      end

      def render_repository_badge(platform, owner, name)
        badge = render_badge.repository(platform: platform, owner: owner, name: name, period_start: store.latest_period)
        halt 404 unless badge

        content_type 'image/svg+xml'
        public_badge_cache!('repository-badge', platform, owner, name, store.latest_period)
        settings.badge_renderer.svg(badge, home_url: app_home_url)
      end

      def ranked_github_profile(login)
        profile = show_user_profile.call(platform: 'github', login: login, period_start: store.latest_period)
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

      def own_repository?(repository)
        current_user &&
          current_user.fetch(:platform) == repository.fetch(:platform) &&
          current_user.fetch(:github_id).to_i == repository.fetch(:owner_github_id).to_i
      end

      def show_discord_panel_for(profile)
        show_discord_panel.call(
          platform: profile.fetch(:platform),
          source_id: profile.fetch(:github_id),
          period_start: @period
        )
      end

      def discord_channel_url
        guild_id = ENV.fetch('DISCORD_GUILD_ID', '').strip
        channel_id = ENV.fetch('DISCORD_INVITE_CHANNEL_ID', '').strip
        return if guild_id.empty? || channel_id.empty?

        "https://discord.com/channels/#{guild_id}/#{channel_id}"
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
        access = show_discord_panel.call(
          platform: profile.fetch(:platform),
          source_id: profile.fetch(:github_id),
          period_start: store.latest_period
        ).access
        desired_role_ids = discord_role_map.role_ids(access.fetch(:role_keys))
        sync_discord_access(discord_user.fetch('id'), access_token, profile.fetch(:login), desired_role_ids)
        post_discord_welcome(discord_user.fetch('id'), profile, access, desired_role_ids)
      end

      def sync_discord_access(discord_user_id, access_token, github_login, desired_role_ids)
        discord_gateway.sync_member(
          discord_user_id: discord_user_id,
          access_token: access_token,
          github_login: github_login,
          desired_role_ids: desired_role_ids,
          managed_role_ids: discord_role_map.managed_role_ids
        )
      end

      def post_discord_welcome(discord_user_id, profile, access, role_ids)
        channel_id = ENV.fetch('DISCORD_WELCOME_CHANNEL_ID', configuration.discord_invite_channel_id)
        welcome = { channel_id: channel_id, discord_user_id: discord_user_id, profile: profile, access: access }
        discord_gateway.post_welcome_message(**welcome, role_ids: role_ids)
      rescue Auth::DiscordGateway::Error
        nil
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
        badge = render_badge.user(platform: platform, login: login, period_start: store.latest_period)
        halt 404 unless badge

        content_type 'image/svg+xml'
        public_badge_cache!('user-badge', platform, login, store.latest_period)
        settings.badge_renderer.svg(badge, home_url: app_home_url)
      end

      def render_ranking_detail(period_slug, scope, kind, metric)
        halt 404 unless ranking_metric?(kind, metric)

        @scope = scope_data(scope)
        @period_slug = period_slug
        @period = period_for(period_slug)
        @kind = kind
        @metric = metric
        public_html_cache!('ranking-detail', period_slug, scope, kind, metric, @period, public_cache_revision(@period))
        @ranking = show_ranking_detail.call(scope: scope, kind: kind, metric: metric, period_start: @period)
        @title = "#{scope_name(@scope)} #{ranking_title(kind, metric)}"
        @description = "#{ranking_title(kind, metric)} - #{scope_name(@scope)}."
        @canonical_path = ranking_path(kind, metric, period_slug: period_slug, scope_slug: scope)
        erb :ranking_detail
      end

      def period_for(period_slug)
        return store.latest_period if period_slug == 'latest'

        halt 404 unless period_slug.match?(/\A\d{4}-\d{2}\z/)

        period_start = Shared::Domain::Period.parse(period_slug).start_date.to_s
        store.recorded_period?(period_start) ? period_start : halt(404)
      rescue Date::Error
        halt 404
      end

      def store
        @store ||= Infrastructure::SQLiteStore.new(configuration.database_path).migrate!
      end

      def show_rankings
        @show_rankings ||= Contexts::Publication::Application::ShowRankings.new(ranking_read_model: store)
      end

      def show_ranking_detail
        @show_ranking_detail ||= Contexts::Publication::Application::ShowRankingDetail.new(ranking_read_model: store)
      end

      def list_editions
        @list_editions ||= Contexts::Publication::Application::ListEditions.new(edition_read_model: store)
      end

      def show_user_profile
        @show_user_profile ||= Contexts::Publication::Application::ShowUserProfile.new(profile_read_model: store)
      end

      def show_repository_profile
        @show_repository_profile ||=
          Contexts::Publication::Application::ShowRepositoryProfile.new(profile_read_model: store)
      end

      def render_badge
        @render_badge ||= Contexts::Publication::Application::RenderBadge.new(profile_read_model: store)
      end

      def show_discord_panel
        @show_discord_panel ||= Contexts::Community::Application::ShowDiscordPanel.new(
          connection_repository: store,
          access_read_model: store
        )
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

        Contexts::Ranking::Domain::LocationCatalog::CITY_BY_SLUG.fetch(scope)
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

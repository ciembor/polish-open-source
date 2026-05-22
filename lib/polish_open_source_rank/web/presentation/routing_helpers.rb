# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Presentation
      # rubocop:disable Metrics/ModuleLength
      module RoutingHelpers
        def current_locale
          @locale || settings.default_locale
        end

        def current_locale?(locale)
          current_locale == locale
        end

        def locale_path(locale)
          query = Rack::Utils.parse_nested_query(request.query_string)
          query.delete('lang')
          path = localized_public_path(unlocalized_request_path, locale: locale)
          return path if query.empty?

          "#{path}?#{Rack::Utils.build_query(query)}"
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

        def user_profile_path(user)
          platform = Rack::Utils.escape_path(user.fetch(:platform, 'github'))
          login = Rack::Utils.escape_path(user.fetch(:login))
          localized_public_path("/users/#{platform}/#{login}", locale: current_locale)
        end

        def repository_profile_path(repository)
          platform = Rack::Utils.escape_path(repository.fetch(:platform, 'github'))
          owner, name = repository.fetch(:full_name).split('/', 2)
          localized_public_path(
            "/repositories/#{platform}/#{Rack::Utils.escape_path(owner)}/#{Rack::Utils.escape_path(name)}",
            locale: current_locale
          )
        end

        def period_base_path(period_slug)
          path = period_slug.nil? || period_slug == 'latest' ? '/latest' : "/#{period_slug}"
          localized_public_path(path, locale: current_locale)
        end

        def app_path(path)
          "#{configuration.app_base_path}#{path}"
        end

        def editions_path(year = nil)
          localized_public_path(year ? "/editions/#{year}" : '/editions', locale: current_locale)
        end

        def canonical_url
          full_url(canonical_path)
        end

        def structured_data
          JSON.pretty_generate(structured_data_payload)
        end

        def alternate_locale_urls
          return {} unless localized_page?

          App::SUPPORTED_LOCALES.to_h do |locale|
            [locale, full_url(localized_public_path(canonical_path, locale: locale))]
          end
        end

        def social_image_url
          full_url(app_path(social_image_path))
        end

        def open_graph_type
          return 'profile' if @profile || @repository

          'website'
        end

        def og_locale
          current_locale == 'pl' ? 'pl_PL' : 'en_US'
        end

        def og_alternate_locales
          App::SUPPORTED_LOCALES.reject { |locale| locale == current_locale }.map do |locale|
            locale == 'pl' ? 'pl_PL' : 'en_US'
          end
        end

        def configuration
          @configuration ||= Configuration.load
        end

        private

        def structured_data_payload
          nodes = [website_schema, page_schema]
          breadcrumbs = breadcrumb_schema
          nodes << breadcrumbs if breadcrumbs
          nodes.compact
        end

        def website_schema
          return unless localized_page?

          {
            '@context' => 'https://schema.org',
            '@type' => 'WebSite',
            'name' => 'Polish Open Source',
            'url' => full_url(period_base_path('latest')),
            'inLanguage' => current_locale
          }
        end

        def page_schema
          base = {
            '@context' => 'https://schema.org',
            '@type' => structured_data_type,
            'name' => @title,
            'description' => @description,
            'url' => canonical_url,
            'inLanguage' => current_locale
          }

          base.merge(page_schema_details)
        end

        def page_schema_details
          return { 'about' => { '@type' => 'Organization', 'name' => 'Polish Open Source Rank' } } if about_page?
          return { 'mainEntity' => collection_schema } if collection_page?
          return { 'mainEntity' => profile_schema } if profile_page?
          return repository_schema if repository_page?

          {}
        end

        def collection_schema
          return ranking_collection_schema if @ranking
          return rankings_overview_schema if @user_rankings || @repository_rankings
          return editions_collection_schema if @editions

          nil
        end

        def ranking_collection_schema
          {
            '@type' => 'ItemList',
            'name' => ranking_title(@kind, @metric),
            'numberOfItems' => @ranking.length,
            'itemListElement' => item_list_elements(@ranking) { |row| ranking_row_schema(row) }
          }
        end

        def rankings_overview_schema
          sections = ranking_overview_sections
          {
            '@type' => 'ItemList',
            'name' => @title,
            'numberOfItems' => sections.length,
            'itemListElement' => sections.each_with_index.map do |section, index|
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'item' => section
              }
            end
          }
        end

        def ranking_overview_sections
          user_ranking_overview_sections + repository_ranking_overview_sections
        end

        def user_ranking_overview_sections
          [
            item_list_schema(
              t('rankings.top_10_stars'),
              @user_rankings.fetch(:top).first(10)
            ) { |row| user_schema(row) },
            item_list_schema(
              t('rankings.trending_10_month'),
              @user_rankings.fetch(:trending).first(10)
            ) { |row| user_schema(row) },
            item_list_schema(
              t('rankings.users_activity_month'),
              @user_rankings.fetch(:active).first(10)
            ) { |row| user_schema(row) }
          ]
        end

        def repository_ranking_overview_sections
          [
            item_list_schema(
              t('rankings.top_10_stars'),
              @repository_rankings.fetch(:top).first(10)
            ) { |row| repository_list_schema(row) },
            item_list_schema(
              t('rankings.trending_10_month'),
              @repository_rankings.fetch(:trending).first(10)
            ) { |row| repository_list_schema(row) }
          ]
        end

        def editions_collection_schema
          {
            '@type' => 'ItemList',
            'name' => @title,
            'numberOfItems' => @editions.length,
            'itemListElement' => @editions.each_with_index.map do |edition, index|
              period_slug = Date.parse(edition.fetch(:period_start)).strftime('%Y-%m')
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'url' => full_url(period_base_path(period_slug)),
                'name' => period_label(edition.fetch(:period_start))
              }
            end
          }
        end

        def profile_schema
          return repository_owner_profile_schema if @repository

          profile = {
            '@type' => 'Person',
            'name' => @profile[:name].to_s.empty? ? @profile.fetch(:login) : @profile[:name],
            'alternateName' => @profile.fetch(:login),
            'url' => canonical_url,
            'sameAs' => @profile.fetch(:html_url)
          }
          add_optional_profile_fields(profile)
          profile
        end

        def add_optional_profile_fields(profile)
          profile['image'] = @profile[:avatar_url] if present_value?(@profile[:avatar_url])
          location = @profile[:city] || @profile[:country]
          profile['homeLocation'] = location if present_value?(location)
        end

        def repository_schema
          {
            'codeRepository' => @repository.fetch(:html_url),
            'programmingLanguage' => @repository[:language],
            'author' => repository_owner_profile_schema
          }.compact
        end

        def repository_owner_profile_schema
          {
            '@type' => 'Person',
            'name' => @repository.fetch(:owner_login),
            'url' => full_url(repository_owner_profile_path)
          }
        end

        def repository_owner_profile_path
          user_profile_path(platform: @repository.fetch(:platform), login: @repository.fetch(:owner_login))
        end

        def item_list_schema(name, rows, &)
          {
            '@type' => 'ItemList',
            'name' => name,
            'numberOfItems' => rows.length,
            'itemListElement' => item_list_elements(rows, &)
          }
        end

        def item_list_elements(rows, &)
          rows.each_with_index.map do |row, index|
            {
              '@type' => 'ListItem',
              'position' => index + 1,
              'item' => yield(row)
            }
          end
        end

        def ranking_row_schema(row)
          return user_schema(row) if @kind == 'users'

          repository_list_schema(row)
        end

        def user_schema(row)
          {
            '@type' => 'Person',
            'name' => row[:name].to_s.empty? ? row.fetch(:login) : row[:name],
            'alternateName' => row.fetch(:login),
            'url' => full_url(user_profile_path(row)),
            'sameAs' => row.fetch(:html_url)
          }
        end

        def repository_list_schema(row)
          {
            '@type' => 'SoftwareSourceCode',
            'name' => row.fetch(:full_name),
            'url' => full_url(repository_profile_path(row)),
            'codeRepository' => row.fetch(:html_url)
          }.tap do |repository|
            repository['description'] = row[:description] if present_value?(row[:description])
            repository['programmingLanguage'] = row[:language] if present_value?(row[:language])
          end
        end

        def breadcrumb_schema
          items = breadcrumb_items
          return if items.length < 2

          {
            '@context' => 'https://schema.org',
            '@type' => 'BreadcrumbList',
            'itemListElement' => items.each_with_index.map do |item, index|
              {
                '@type' => 'ListItem',
                'position' => index + 1,
                'name' => item.fetch(:name),
                'item' => full_url(item.fetch(:path))
              }
            end
          }
        end

        def breadcrumb_items
          items = [{ name: t('scope.poland'), path: period_base_path('latest') }]
          items << { name: scope_name(@scope), path: scope_path(@scope) } if city_scope?
          items.concat(current_page_breadcrumbs)
          items
        end

        def current_page_breadcrumbs
          return [{ name: ranking_title(@kind, @metric), path: canonical_path }] if @ranking
          return edition_breadcrumbs if @editions
          return [{ name: @profile.fetch(:login), path: canonical_path }] if @profile
          return [{ name: @repository.fetch(:full_name), path: canonical_path }] if @repository
          return [{ name: t('about.title'), path: canonical_path }] if about_page?
          return [{ name: @title, path: canonical_path }] if canonical_path != period_base_path('latest')

          []
        end

        def edition_breadcrumbs
          breadcrumbs = [{ name: t('editions.title'), path: editions_path }]
          breadcrumbs << { name: @year.to_s, path: canonical_path } if @year
          breadcrumbs
        end

        def canonical_path
          path = @canonical_path || request.path_info
          return path if localized_path?(path)
          return localized_public_path(path, locale: current_locale) if localized_page_path?(path)

          path
        end

        def localized_page?
          localized_page_path?(canonical_path)
        end

        def localized_public_path(path, locale:)
          Localization::PublicPathPolicy.localized(path: path, locale: locale, default_locale: settings.default_locale)
        end

        def localized_path?(path)
          !Localization::PublicPathPolicy.locale_prefix(path).nil?
        end

        def localized_page_path?(path)
          Localization::PublicPathPolicy.localizable?(path)
        end

        def unlocalized_request_path
          env.fetch('polish_open_source_rank.unlocalized_path', request.path_info)
        end

        def full_url(path)
          base_url = configuration.public_base_url.delete_suffix('/')
          "#{base_url}#{path}"
        end

        def social_image_path
          return '/images/pos_cut.png' if about_page?
          return '/images/polish_open_source_join.webp' if @editions
          return '/images/pos.png' if profile_page? || repository_page?

          '/images/polish_open_source_banner.webp'
        end

        def present_value?(value)
          !value.to_s.empty?
        end

        def about_page?
          @canonical_path == '/about'
        end

        def collection_page?
          structured_data_type == 'CollectionPage'
        end

        def profile_page?
          structured_data_type == 'ProfilePage'
        end

        def repository_page?
          structured_data_type == 'SoftwareSourceCode'
        end

        def city_scope?
          @scope && @scope.fetch(:slug) != 'poland'
        end

        def structured_data_type
          return 'AboutPage' if about_page?
          return 'SoftwareSourceCode' if @repository
          return 'ProfilePage' if @profile
          return 'CollectionPage' if @user_rankings || @editions || @ranking

          'WebPage'
        end
      end
      # rubocop:enable Metrics/ModuleLength
    end
  end
end

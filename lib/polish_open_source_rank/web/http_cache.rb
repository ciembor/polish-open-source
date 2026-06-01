# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module HttpCache
      def no_store!
        headers 'Cache-Control' => 'no-store'
      end

      def public_html_cache!(*parts)
        cache_response!(
          public_cache_allowed? ? public_html_cache_control : 'private, no-cache',
          'html',
          current_locale,
          html_revision,
          *parts
        )
      end

      def profile_cache!(profile)
        cache_control = own_profile?(profile) ? 'private, no-cache' : public_html_cache_control
        cache_response!(
          cache_control,
          'profile',
          current_locale,
          html_revision,
          profile.fetch(:platform),
          profile.fetch(:github_id),
          @period,
          public_cache_revision(@period)
        )
      end

      def repository_profile_cache!(repository)
        cache_control = own_repository?(repository) ? 'private, no-cache' : public_html_cache_control
        cache_response!(
          cache_control,
          'repository-profile',
          current_locale,
          html_revision,
          repository.fetch(:platform),
          repository.fetch(:github_id),
          @period,
          public_cache_revision(@period)
        )
      end

      def public_badge_cache!(*parts)
        period = parts.last
        cache_response!(
          'public, max-age=3600, stale-while-revalidate=86400',
          'badge',
          *parts,
          public_cache_revision(period)
        )
      end

      def cache_response!(cache_control, *etag_parts)
        response_headers = { 'Cache-Control' => cache_control, 'ETag' => cache_etag(*etag_parts) }
        vary = cache_vary_header(cache_control)
        response_headers['Vary'] = vary if vary
        headers response_headers
        halt 304 if request.get? && etag_matches?(response.headers.fetch('ETag'))
      end

      def cache_etag(*parts)
        %("#{Digest::SHA256.hexdigest(parts.compact.join('|'))}")
      end

      def etag_matches?(etag)
        request.get_header('HTTP_IF_NONE_MATCH').to_s.split(',').map(&:strip).include?(etag)
      end

      def public_cache_allowed?
        current_user.nil?
      end

      def public_html_cache_control
        'public, max-age=60, stale-while-revalidate=300'
      end

      def cache_vary_header(cache_control)
        return 'Cookie' unless cache_control.start_with?('public')

        nil
      end
    end
  end
end

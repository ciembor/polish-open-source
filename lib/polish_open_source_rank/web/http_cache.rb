# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module HttpCache
      def no_store!
        headers 'Cache-Control' => 'no-store'
      end

      def public_html_cache!(*parts)
        cache_response!(
          'html',
          current_locale,
          html_revision,
          *parts,
          cache_control: public_cache_allowed? ? public_html_cache_control : 'private, no-cache',
          vary_cookie: true
        )
      end

      def profile_cache!(profile)
        cache_control = own_profile?(profile) ? 'private, no-cache' : public_html_cache_control
        cache_response!(
          'profile',
          current_locale,
          html_revision,
          profile.fetch(:platform),
          profile.fetch(:github_id),
          @period,
          public_cache_revision(@period),
          cache_control: cache_control,
          vary_cookie: true
        )
      end

      def repository_profile_cache!(repository)
        cache_control = own_repository?(repository) ? 'private, no-cache' : public_html_cache_control
        cache_response!(
          'repository-profile',
          current_locale,
          html_revision,
          repository.fetch(:platform),
          repository.fetch(:github_id),
          @period,
          public_cache_revision(@period),
          cache_control: cache_control,
          vary_cookie: true
        )
      end

      def public_badge_cache!(*parts)
        period = parts.last
        cache_response!(
          'badge',
          *parts,
          public_cache_revision(period),
          cache_control: 'public, max-age=3600, stale-while-revalidate=86400, stale-if-error=86400',
          vary_cookie: false
        )
      end

      def negative_public_cache!(*parts)
        cache_response!(
          'not-found',
          current_locale,
          html_revision,
          *parts,
          cache_control: public_cache_allowed? ? negative_public_cache_control : 'private, no-cache',
          vary_cookie: true
        )
      end

      def halt_negative_public_404!(*parts)
        negative_public_cache!(*parts)
        halt 404
      end

      def cache_response!(*etag_parts, cache_control:, vary_cookie:)
        response_headers = { 'Cache-Control' => cache_control, 'ETag' => cache_etag(*etag_parts) }
        response_headers['Vary'] = 'Cookie' if vary_cookie
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
        'public, max-age=60, stale-while-revalidate=300, stale-if-error=86400'
      end

      def negative_public_cache_control
        'public, max-age=30, stale-while-revalidate=120, stale-if-error=300'
      end
    end
  end
end

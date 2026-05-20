# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module HttpCache
      def no_store!
        headers 'Cache-Control' => 'no-store'
      end

      def public_html_cache!(*parts)
        cache_response!(
          public_cache_allowed? ? 'public, max-age=0, must-revalidate' : 'private, no-cache',
          'html',
          current_locale,
          html_revision,
          *parts
        )
      end

      def profile_cache!(profile)
        cache_control = own_profile?(profile) ? 'private, no-cache' : 'public, max-age=0, must-revalidate'
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

      def public_badge_cache!(*parts)
        period = parts.last
        cache_response!(
          'public, max-age=300, stale-while-revalidate=3600',
          'badge',
          *parts,
          public_cache_revision(period)
        )
      end

      def cache_response!(cache_control, *etag_parts)
        headers 'Cache-Control' => cache_control, 'ETag' => cache_etag(*etag_parts), 'Vary' => cache_vary_header
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

      def cache_vary_header
        'Accept-Language, Cookie'
      end
    end
  end
end

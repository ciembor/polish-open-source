# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module Registries
          module RegistryClientHelpers
            module_function

            def escaped_segment(value)
              URI.encode_www_form_component(value).tr('+', '%20')
            end

            def fetch_error(result)
              Domain::RegistryFetchResult.new(
                status: result.status,
                error: result.error,
                retry_after: result.retry_after
              )
            end

            def first_present(hash, *keys)
              keys.each do |key|
                value = hash[key]
                return value unless value.nil? || value == ''
              end
              nil
            end

            def license(value)
              value.is_a?(Array) ? value.join(', ') : value
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          module PackageRepositoryLinkSql
            module_function

            def representative_url
              "substr(#{representative_key}, instr(#{representative_key}, char(31)) + 1) AS repository_html_url"
            end

            def joins
              <<~SQL
                LEFT JOIN repositories user_repositories
                  ON scans.repository_kind = 'user'
                 AND user_repositories.platform = scans.platform
                 AND user_repositories.github_id = scans.repository_source_id
                LEFT JOIN organization_repositories org_repositories
                  ON scans.repository_kind = 'organization'
                 AND org_repositories.platform = scans.platform
                 AND org_repositories.github_id = scans.repository_source_id
              SQL
            end

            def representative_key
              'MIN(scans.full_name || char(31) || COALESCE(user_repositories.html_url, org_repositories.html_url))'
            end
            private_class_method :representative_key
          end
        end
      end
    end
  end
end

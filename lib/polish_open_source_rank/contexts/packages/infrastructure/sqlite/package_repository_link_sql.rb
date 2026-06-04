# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Packages
      module Infrastructure
        module SQLite
          module PackageRepositoryLinkSql
            module_function

            def representative_url
              representative_value('COALESCE(user_repositories.html_url, org_repositories.html_url)',
                                   'repository_html_url')
            end

            def representative_description
              representative_value('COALESCE(user_repositories.description, org_repositories.description)',
                                   'repository_description')
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

            def representative_value(expression, alias_name)
              key = "MIN(scans.full_name || char(31) || COALESCE(#{expression}, ''))"

              "substr(#{key}, instr(#{key}, char(31)) + 1) AS #{alias_name}"
            end
            private_class_method :representative_value
          end
        end
      end
    end
  end
end

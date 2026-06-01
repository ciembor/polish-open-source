# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Publication
      module Infrastructure
        module SQLite
          # Shared public identity queries used by profile read models and jobs.
          module SQLitePublicIdentityQueries
            def public_user_identities
              database.fetch_all(<<~SQL)
                SELECT platform, login
                FROM users
                ORDER BY platform ASC, login COLLATE NOCASE ASC
              SQL
            end

            def public_organization_identities
              database.fetch_all(<<~SQL)
                SELECT platform, login
                FROM organizations
                ORDER BY platform ASC, login COLLATE NOCASE ASC
              SQL
            end
          end
        end
      end
    end
  end
end

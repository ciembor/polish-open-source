# frozen_string_literal: true

require "date"
require "fileutils"
require "json"
require "pathname"
require "time"

module PolishGithubRank
  def self.root
    Pathname(__dir__).parent
  end
end

require_relative "polish_github_rank/configuration"
require_relative "polish_github_rank/domain/location_catalog"
require_relative "polish_github_rank/domain/location_classifier"
require_relative "polish_github_rank/application/month_period"
require_relative "polish_github_rank/application/monthly_snapshot_job"
require_relative "polish_github_rank/infrastructure/github_client"
require_relative "polish_github_rank/infrastructure/github_gateway"
require_relative "polish_github_rank/infrastructure/sqlite_store"
require_relative "polish_github_rank/application/monthly_snapshot_command"

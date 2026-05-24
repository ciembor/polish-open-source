# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module InternalController
        private

        def format_monitor_time(value)
          return 'n/a' unless value

          Time.parse(value).localtime.strftime('%H:%M:%S %Z')
        end

        def format_duration_ms(value)
          return 'n/a' unless value

          value = value.to_i
          return "#{value}ms" if value < 1000

          format_duration_seconds((value / 1000.0).round)
        end

        def format_duration_seconds(value)
          return 'n/a' unless value

          seconds = value.to_i
          return "#{seconds}s" if seconds < 60

          minutes, remaining_seconds = seconds.divmod(60)
          return "#{minutes}m #{remaining_seconds}s" if minutes < 60

          hours, remaining_minutes = minutes.divmod(60)
          "#{hours}h #{remaining_minutes}m"
        end
      end
    end
  end
end

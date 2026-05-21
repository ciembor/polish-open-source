# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    module Controllers
      module InternalController
        private

        def chart_context(points, value_key, platforms, carry_forward: false, width: 720, height: 180)
          minutes = points.map { |point| point.fetch(:minute) }.uniq.sort
          max_value = points.map { |point| point.fetch(value_key).to_i }.max.to_i
          {
            points: points,
            value_key: value_key,
            platforms: platforms,
            minutes: minutes,
            max_value: max_value,
            carry_forward: carry_forward,
            width: width,
            height: height
          }
        end

        def chart_axis_values(context)
          max_value = context.fetch(:max_value).to_i
          [max_value, (max_value / 2.0).round, 0]
        end

        def chart_time_ticks(context)
          minutes = context.fetch(:minutes)
          return [] if minutes.empty?

          last_index = minutes.length - 1
          [0, minutes.length / 2, last_index].uniq.map do |index|
            x = minutes.one? ? 0 : (index.to_f / (minutes.length - 1) * context.fetch(:width))
            anchor = index == last_index ? 'end' : 'start'
            { label: format_monitor_time(minutes.fetch(index)), x: x.round(1), anchor: anchor }
          end
        end

        def chart_polyline(context, platform)
          minutes = context.fetch(:minutes)
          return '' if minutes.empty?

          max_value = context.fetch(:max_value)
          return '' if max_value.zero?

          values = chart_values(context, platform)
          minutes.each_with_index.map do |_minute, index|
            x = minutes.one? ? 0 : (index.to_f / (minutes.length - 1) * context.fetch(:width))
            y = context.fetch(:height) - (values.fetch(index).to_f / max_value * context.fetch(:height))
            "#{x.round(1)},#{y.round(1)}"
          end.join(' ')
        end

        def chart_values(context, platform)
          rows = context.fetch(:points).select { |point| point.fetch(:platform) == platform }
          value_by_minute = rows.to_h { |point| [point.fetch(:minute), point.fetch(context.fetch(:value_key)).to_i] }
          current = 0
          context.fetch(:minutes).map do |minute|
            current = value_by_minute.fetch(minute, current)
            context.fetch(:carry_forward) ? current : value_by_minute.fetch(minute, 0)
          end
        end

        def format_monitor_time(value)
          return 'n/a' unless value

          Time.parse(value).localtime.strftime('%H:%M:%S %Z')
        end
      end
    end
  end
end

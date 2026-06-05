# frozen_string_literal: true

module PolishOpenSourceRank
  # Loads dotenv-style key/value files into an environment hash without overwriting existing values.
  class EnvFile
    ASSIGNMENT = /\A(?:export\s+)?(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*=\s*(?<value>.*)\z/

    def initialize(path)
      @path = path
    end

    def apply_to(environment)
      return unless path.file?

      path.each_line(chomp: true) do |line|
        key, value = assignment(line)
        environment[key] ||= value if key
      end
    end

    private

    attr_reader :path

    def assignment(line)
      stripped = line.strip
      return if stripped.empty? || stripped.start_with?('#')

      match = stripped.match(ASSIGNMENT)
      return unless match

      [match[:key], value(match[:value].to_s)]
    end

    def value(raw_value)
      stripped = raw_value.strip
      return unescape_double_quoted(inner_value(stripped)) if quoted?(stripped, '"')
      return inner_value(stripped) if quoted?(stripped, "'")

      stripped.split(/\s+#/, 2).fetch(0, '').strip
    end

    def quoted?(value, quote)
      value.start_with?(quote) && value.end_with?(quote)
    end

    def inner_value(value)
      value[1...-1]
    end

    def unescape_double_quoted(value)
      value
        .gsub('\"', '"')
        .gsub('\\\\', '\\')
    end
  end
end

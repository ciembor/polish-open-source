# frozen_string_literal: true

module PolishGithubRank
  module Domain
    module LocationCatalog
      COUNTRY = 'Poland'
      COUNTRY_VARIANTS = %w[Polska polska Poland poland].freeze

      CITY_DATA = [
        ['warszawa', 'Warszawa', %w[Warszawa warszawa Warsaw warsaw], true],
        ['krakow', 'Kraków', %W[Krak\u00F3w krak\u00F3w Krakow krakow Cracow cracow], true],
        ['wroclaw', 'Wrocław', %W[Wroc\u0142aw wroc\u0142aw Wroclaw wroclaw], true],
        ['lodz', 'Łódź', %W[\u0141\u00F3d\u017A \u0142\u00F3d\u017A Lodz lodz], true],
        ['poznan', 'Poznań', %W[Pozna\u0144 pozna\u0144 Poznan poznan], true],
        ['gdansk', 'Gdańsk', %W[Gda\u0144sk gda\u0144sk Gdansk gdansk]],
        ['szczecin', 'Szczecin', %w[Szczecin szczecin]],
        ['bydgoszcz', 'Bydgoszcz', %w[Bydgoszcz bydgoszcz]],
        ['torun', 'Toruń', %W[Toru\u0144 toru\u0144 Torun torun]],
        ['lublin', 'Lublin', %w[Lublin lublin]],
        ['bialystok', 'Białystok', %W[Bia\u0142ystok bia\u0142ystok Bialystok bialystok]],
        ['katowice', 'Katowice', %w[Katowice katowice]],
        ['kielce', 'Kielce', %w[Kielce kielce]],
        ['olsztyn', 'Olsztyn', %w[Olsztyn olsztyn]],
        ['opole', 'Opole', %w[Opole opole]],
        ['rzeszow', 'Rzeszów', %W[Rzesz\u00F3w rzesz\u00F3w Rzeszow rzeszow]],
        ['zielona-gora', 'Zielona Góra', ['Zielona Góra', 'zielona góra', 'Zielona Gora', 'zielona gora']],
        ['gorzow-wielkopolski', 'Gorzów Wielkopolski',
         ['Gorzów Wielkopolski', 'gorzów wielkopolski', 'Gorzow Wielkopolski', 'gorzow wielkopolski',
          'Gorzów Wlkp', 'Gorzow Wlkp']]
      ].freeze

      CITIES = CITY_DATA.map do |slug, name, variants, primary|
        { slug: slug, name: name, variants: variants }.tap { |city| city[:primary] = true if primary }
      end.freeze

      CITY_BY_SLUG = CITIES.to_h { |city| [city.fetch(:slug), city] }.freeze

      module_function

      def city_slugs
        CITY_BY_SLUG.keys
      end

      def city_name(slug)
        CITY_BY_SLUG.fetch(slug).fetch(:name)
      end

      def scopes
        [{ slug: 'poland', name: 'Polska', type: :country }] +
          CITIES.map { |city| city.slice(:slug, :name).merge(type: :city) }
      end

      def primary_city_scopes
        CITIES.select { |city| city[:primary] }.map { |city| city.slice(:slug, :name).merge(type: :city) }
      end

      def secondary_city_scopes
        CITIES.reject { |city| city[:primary] }.map { |city| city.slice(:slug, :name).merge(type: :city) }
      end

      def search_terms
        (COUNTRY_VARIANTS + CITIES.flat_map { |city| city.fetch(:variants) }).uniq
      end
    end
  end
end

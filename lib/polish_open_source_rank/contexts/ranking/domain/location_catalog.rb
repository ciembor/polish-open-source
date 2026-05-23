# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        module LocationCatalog
          COUNTRY = 'Poland'
          COUNTRY_VARIANTS = %w[Polska polska Poland poland].freeze

          CITY_DATA = [
            ['warszawa', 'Warszawa', %w[Warszawa Warsaw], true],
            ['krakow', 'Kraków', %w[Kraków Krakow Cracow], true],
            ['wroclaw', 'Wrocław', %w[Wrocław Wroclaw], true],
            ['lodz', 'Łódź', %w[Łódź Lodz], true],
            ['poznan', 'Poznań', %w[Poznań Poznan], true],
            ['gdansk', 'Gdańsk', %w[Gdańsk Gdansk]],
            ['szczecin', 'Szczecin', ['Szczecin']],
            ['lublin', 'Lublin', ['Lublin']],
            ['bydgoszcz', 'Bydgoszcz', ['Bydgoszcz']],
            ['bialystok', 'Białystok', %w[Białystok Bialystok]],
            ['katowice', 'Katowice', ['Katowice']],
            ['gdynia', 'Gdynia', ['Gdynia']],
            ['czestochowa', 'Częstochowa', %w[Częstochowa Czestochowa]],
            ['rzeszow', 'Rzeszów', %w[Rzeszów Rzeszow]],
            ['torun', 'Toruń', %w[Toruń Torun]],
            ['radom', 'Radom', ['Radom']],
            ['sosnowiec', 'Sosnowiec', ['Sosnowiec']],
            ['kielce', 'Kielce', ['Kielce']],
            ['gliwice', 'Gliwice', ['Gliwice']],
            ['olsztyn', 'Olsztyn', ['Olsztyn']],
            ['bielsko-biala', 'Bielsko-Biała', ['Bielsko-Biała', 'Bielsko Biała', 'Bielsko-Biala', 'Bielsko Biala']],
            ['zabrze', 'Zabrze', ['Zabrze']],
            ['bytom', 'Bytom', ['Bytom']],
            ['zielona-gora', 'Zielona Góra', ['Zielona Góra', 'Zielona Gora']],
            ['rybnik', 'Rybnik', ['Rybnik']],
            ['ruda-slaska', 'Ruda Śląska', ['Ruda Śląska', 'Ruda Slaska']],
            ['opole', 'Opole', ['Opole']],
            ['tychy', 'Tychy', ['Tychy']],
            ['gorzow-wielkopolski', 'Gorzów Wielkopolski',
             ['Gorzów Wielkopolski', 'Gorzow Wielkopolski', 'Gorzów Wlkp', 'Gorzow Wlkp']],
            ['dabrowa-gornicza', 'Dąbrowa Górnicza', ['Dąbrowa Górnicza', 'Dabrowa Gornicza']],
            ['elblag', 'Elbląg', %w[Elbląg Elblag]],
            ['plock', 'Płock', %w[Płock Plock]],
            ['koszalin', 'Koszalin', ['Koszalin']],
            ['tarnow', 'Tarnów', %w[Tarnów Tarnow]]
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
  end
end

# frozen_string_literal: true

module PolishOpenSourceRank
  module Contexts
    module Ranking
      module Domain
        module LocationCatalog
          COUNTRY = 'Poland'
          COUNTRY_VARIANTS = %w[Polska polska Poland poland].freeze
          FOREIGN_COUNTRY_NAMES = [
            'Afghanistan|Albania|Algeria|Andorra|Angola|Antigua and Barbuda|Argentina|Armenia|',
            'Australia|Austria|Azerbaijan|Bahamas|Bahrain|Bangladesh|Barbados|Belarus|Belgium|',
            'Belize|Benin|Bhutan|Bolivia|Bosnia and Herzegovina|Botswana|Brazil|Brunei|Bulgaria|',
            'Burkina Faso|Burundi|Cambodia|Cameroon|Canada|Cape Verde|Cabo Verde|Central African Republic|',
            'Chad|Chile|China|Colombia|Comoros|Congo|Costa Rica|Croatia|Cuba|Cyprus|',
            'Czech Republic|Czechia|Denmark|Djibouti|Dominica|Dominican Republic|Ecuador|Egypt|',
            'El Salvador|Equatorial Guinea|Eritrea|Estonia|Eswatini|Ethiopia|Fiji|Finland|',
            'France|Gabon|Gambia|Georgia|Germany|Ghana|Greece|Grenada|Guatemala|Guinea|',
            'Guinea-Bissau|Guyana|Haiti|Honduras|Hungary|Iceland|India|Indonesia|Iran|Iraq|',
            "Ireland|Israel|Italy|Ivory Coast|Cote d'Ivoire|Jamaica|Japan|Jordan|Kazakhstan|Kenya|Kiribati|",
            'Kuwait|Kyrgyzstan|Laos|Latvia|Lebanon|Lesotho|Liberia|Libya|Liechtenstein|',
            'Lithuania|Luxembourg|Madagascar|Malawi|Malaysia|Maldives|Mali|Malta|',
            'Marshall Islands|Mauritania|Mauritius|Mexico|Micronesia|Moldova|Monaco|Mongolia|',
            'Montenegro|Morocco|Mozambique|Myanmar|Namibia|Nauru|Nepal|Netherlands|New Zealand|',
            'Nicaragua|Niger|Nigeria|North Korea|North Macedonia|Norway|Oman|Pakistan|Palau|',
            'Palestine|Panama|Papua New Guinea|Paraguay|Peru|Philippines|Portugal|Qatar|',
            'Romania|Russia|Rwanda|Saint Kitts and Nevis|Saint Lucia|',
            'Saint Vincent and the Grenadines|Samoa|San Marino|Sao Tome and Principe|',
            'Saudi Arabia|Senegal|Serbia|Seychelles|Sierra Leone|Singapore|Slovakia|Slovenia|',
            'Solomon Islands|Somalia|South Africa|South Korea|South Sudan|Spain|Sri Lanka|',
            'Sudan|Suriname|Sweden|Switzerland|Syria|Taiwan|Tajikistan|Tanzania|Thailand|',
            'Timor-Leste|Togo|Tonga|Trinidad and Tobago|Tunisia|Turkey|Turkmenistan|Tuvalu|',
            'Uganda|Ukraine|United Arab Emirates|United Kingdom|UK|U.K.|United States|',
            'United States of America|USA|U.S.A.|U.S.|Uruguay|Uzbekistan|',
            'Vanuatu|Vatican City|Venezuela|Vietnam|Yemen|Zambia|Zimbabwe'
          ].join.split('|').freeze

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

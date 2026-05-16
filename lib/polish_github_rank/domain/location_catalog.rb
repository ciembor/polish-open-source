# frozen_string_literal: true

module PolishGithubRank
  module Domain
    module LocationCatalog
      COUNTRY = 'Poland'
      COUNTRY_VARIANTS = %w[Polska polska Poland poland].freeze

      CITIES = [
        {
          slug: 'krakow',
          name: 'Kraków',
          variants: %W[Krak\u00F3w krak\u00F3w Krakow krakow Cracow cracow]
        },
        {
          slug: 'wroclaw',
          name: 'Wrocław',
          variants: %W[Wroc\u0142aw wroc\u0142aw Wroclaw wroclaw]
        },
        {
          slug: 'warszawa',
          name: 'Warszawa',
          variants: %w[Warszawa warszawa Warsaw warsaw]
        },
        {
          slug: 'gdansk',
          name: 'Gdańsk',
          variants: %W[Gda\u0144sk gda\u0144sk Gdansk gdansk]
        },
        {
          slug: 'poznan',
          name: 'Poznań',
          variants: %W[Pozna\u0144 pozna\u0144 Poznan poznan]
        },
        {
          slug: 'szczecin',
          name: 'Szczecin',
          variants: %w[Szczecin szczecin]
        },
        {
          slug: 'lodz',
          name: 'Łódź',
          variants: %W[\u0141\u00F3d\u017A \u0142\u00F3d\u017A Lodz lodz]
        }
      ].freeze

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

      def search_terms
        (COUNTRY_VARIANTS + CITIES.flat_map { |city| city.fetch(:variants) }).uniq
      end
    end
  end
end

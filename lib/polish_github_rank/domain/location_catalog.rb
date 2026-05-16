# frozen_string_literal: true

module PolishGithubRank
  module Domain
    module LocationCatalog
      COUNTRY = "Poland"
      COUNTRY_VARIANTS = %w[Polska polska Poland poland].freeze

      CITIES = [
        {
          slug: "krakow",
          name: "Kraków",
          variants: ["Kraków", "kraków", "Krakow", "krakow", "Cracow", "cracow"]
        },
        {
          slug: "wroclaw",
          name: "Wrocław",
          variants: ["Wrocław", "wrocław", "Wroclaw", "wroclaw"]
        },
        {
          slug: "warszawa",
          name: "Warszawa",
          variants: ["Warszawa", "warszawa", "Warsaw", "warsaw"]
        },
        {
          slug: "gdansk",
          name: "Gdańsk",
          variants: ["Gdańsk", "gdańsk", "Gdansk", "gdansk"]
        },
        {
          slug: "poznan",
          name: "Poznań",
          variants: ["Poznań", "poznań", "Poznan", "poznan"]
        },
        {
          slug: "szczecin",
          name: "Szczecin",
          variants: ["Szczecin", "szczecin"]
        },
        {
          slug: "lodz",
          name: "Łódź",
          variants: ["Łódź", "łódź", "Lodz", "lodz"]
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
        [{ slug: "poland", name: "Polska", type: :country }] +
          CITIES.map { |city| city.slice(:slug, :name).merge(type: :city) }
      end

      def search_terms
        (COUNTRY_VARIANTS + CITIES.flat_map { |city| city.fetch(:variants) }).uniq
      end
    end
  end
end


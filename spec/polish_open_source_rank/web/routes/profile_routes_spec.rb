# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Routes::ProfileRoutes do
  subject(:app) do
    Class.new do
      class << self
        attr_reader :routes
      end

      @routes = []

      def self.get(path, &block)
        @routes << [path, block]
      end
    end
  end

  it 'registers user, organization, and repository profile routes' do
    described_class.register(app)

    expect(app.routes.map(&:first)).to eq(
      [
        '/users/:platform/:login/:name_slug',
        '/users/:platform/:login',
        '/organizations/:platform/:login/:name_slug',
        '/organizations/:platform/:login',
        '/repositories/:platform/:owner/:name',
        '/organization-repositories/:platform/:owner/:name'
      ]
    )
  end
end

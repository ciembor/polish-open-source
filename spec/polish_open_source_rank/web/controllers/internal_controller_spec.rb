# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Controllers::InternalController do
  subject(:controller) do
    Class.new do
      include PolishOpenSourceRank::Web::Controllers::InternalController
    end.new
  end

  it 'formats operational durations for monitor tables', :aggregate_failures do
    expect(controller.send(:format_duration_ms, nil)).to eq('n/a')
    expect(controller.send(:format_duration_ms, 999)).to eq('999ms')
    expect(controller.send(:format_duration_ms, 1000)).to eq('1s')
    expect(controller.send(:format_duration_seconds, nil)).to eq('n/a')
    expect(controller.send(:format_duration_seconds, 61)).to eq('1m 1s')
    expect(controller.send(:format_duration_seconds, 3660)).to eq('1h 1m')
  end
end

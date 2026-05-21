# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank do
  it 'eager loads the application constants' do
    expect { described_class.loader.eager_load }.not_to raise_error
  end
end

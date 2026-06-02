# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::ViewHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::ViewHelpers
    end.new
  end

  describe '#safe_external_url' do
    it 'keeps browser-safe HTTP URLs and trims surrounding whitespace' do
      expect(helper.safe_external_url(" https://github.com/alice/app?tab=readme#install \n"))
        .to eq('https://github.com/alice/app?tab=readme#install')
    end

    it 'rejects URLs that should not become public href or src values' do
      expect(helper.safe_external_url('javascript:alert(1)')).to be_nil
      expect(helper.safe_external_url('data:text/html,<script>alert(1)</script>')).to be_nil
      expect(helper.safe_external_url('https://user:password@example.test/path')).to be_nil
      expect(helper.safe_external_url('/relative/path')).to be_nil
      expect(helper.safe_external_url("https://example.test/\nnext")).to be_nil
    end
  end
end

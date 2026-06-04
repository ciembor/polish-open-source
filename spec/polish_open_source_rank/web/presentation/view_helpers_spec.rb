# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::Presentation::ViewHelpers do
  subject(:helper) do
    Class.new do
      include PolishOpenSourceRank::Web::Presentation::ViewHelpers

      attr_accessor :current_locale
    end.new
  end

  before { helper.current_locale = :pl }

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

  describe '#metric_value' do
    it 'keeps full numbers for non-download metrics' do
      expect(helper.metric_value(:stargazers_count, 12_345)).to eq('⭐ 12 345')
    end

    it 'compacts download metrics using Polish units' do
      expect(helper.metric_value(:downloads_30d, 1_000)).to eq('📥 1 tys.')
      expect(helper.metric_value(:downloads_total, 30_000)).to eq('📥 30 tys.')
      expect(helper.metric_value(:downloads_total, 1_500_000)).to eq('📥 1,5 mln')
      expect(helper.metric_value(:downloads_total, 2_000_000_000)).to eq('📥 2 mld')
    end

    it 'compacts download metrics using English units' do
      helper.current_locale = :en

      expect(helper.metric_value(:downloads_30d, 1_000)).to eq('📥 1K')
      expect(helper.metric_value(:downloads_total, 30_000)).to eq('📥 30K')
      expect(helper.metric_value(:downloads_total, 1_500_000)).to eq('📥 1.5M')
      expect(helper.metric_value(:downloads_total, 2_000_000_000)).to eq('📥 2B')
    end
  end

  describe '#star_history_chart_url' do
    it 'builds Star History chart URLs for GitHub repositories' do
      repository = { platform: 'github', full_name: 'alice/app' }

      expect(helper.star_history_chart_url(repository)).to eq(
        'https://api.star-history.com/chart?repos=alice%2Fapp&type=date&legend=top-left'
      )
    end

    it 'links to Star History pages for GitHub repositories' do
      expect(helper.star_history_page_url({ platform: 'github', full_name: 'alice/app' })).to eq(
        'https://www.star-history.com/alice/app'
      )
    end

    it 'rejects unsupported platforms and malformed repository names' do
      expect(helper.star_history_chart_url({ platform: 'gitlab', full_name: 'alice/app' })).to be_nil
      expect(helper.star_history_chart_url({ platform: 'github', full_name: 'alice/app?x=1' })).to be_nil
    end
  end
end

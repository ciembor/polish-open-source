# frozen_string_literal: true

RSpec.describe PolishOpenSourceRank::Web::HtmlRevision do
  it 'tracks all views, public styles, public scripts, and the selected locale' do
    root = Pathname(Dir.mktmpdir)
    create_file(root.join('app/views/pages/index.erb'))
    create_file(root.join('app/views/new_section/show.erb'))
    create_file(root.join('app/public/css/application.css'))
    create_file(root.join('app/public/js/navigation.js'))
    create_file(root.join('config/locales/pl.yml'))

    revision = described_class.new(root: root)

    expect(revision.value(locale: 'pl')).to eq(
      [
        root.join('app/views/pages/index.erb'),
        root.join('app/views/new_section/show.erb'),
        root.join('app/public/css/application.css'),
        root.join('app/public/js/navigation.js'),
        root.join('config/locales/pl.yml')
      ].map { |path| path.mtime.to_i }.max
    )
  end

  def create_file(path)
    path.dirname.mkpath
    path.write("tracked\n")
  end
end

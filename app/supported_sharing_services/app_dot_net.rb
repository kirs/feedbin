class AppDotNet < Service
  URL = 'https://account.app.net/intent/post'

  def initialize(klass = nil)
    @klass = klass
  end

  def share(params)
    entry = Entry.find(params[:entry_id])
    uri = URI.parse(URL)
    uri.query = { 'url' => entry.fully_qualified_url, 'text' => entry.title }.to_query
    {text: render_popover_template(uri.to_s)}
  end

end
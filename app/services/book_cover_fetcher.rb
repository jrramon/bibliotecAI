require "net/http"
require "json"
require "uri"

# Fetches a book cover from Google Books (primary) with an Open Library
# fallback via ISBN. Attaches the downloaded image to `book.cover_image`
# and opportunistically fills in `isbn` if Google returned one.
#
# Both APIs are public, no API key required, free at our expected volume.
class BookCoverFetcher
  GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"
  OPEN_LIBRARY_COVERS = "https://covers.openlibrary.org/b/isbn"
  TIMEOUT = 8
  USER_AGENT = "BibliotecAI/1.0 (https://bibliotecai.local)"
  LOG_TAG = "[BookCoverFetcher]"

  def self.call(...) = new(...).call

  def initialize(book)
    @book = book
  end

  def call
    log "book ##{@book.id} \"#{@book.title}\" / #{@book.author.presence || "(no author)"}"

    if @book.cover_image.attached?
      log "already has cover, skipping"
      return :already_attached
    end

    google = fetch_google
    if google && download_and_attach(google[:url], source: "google_books")
      @book.update(isbn: google[:isbn]) if google[:isbn].present? && @book.isbn.blank?
      log "✓ cover attached from google_books (isbn=#{google[:isbn].inspect})"
      return :google_books
    end

    isbn = @book.isbn.presence || google&.[](:isbn)
    if isbn.present?
      log "trying open_library fallback with isbn=#{isbn}"
      if download_and_attach(open_library_url(isbn), source: "open_library")
        @book.update(isbn: isbn) if @book.isbn.blank?
        log "✓ cover attached from open_library"
        return :open_library
      end
    else
      log "no isbn available, skipping open_library"
    end

    log "✗ no cover found"
    :none
  end

  private

  def fetch_google
    query = build_query
    unless query
      log "google: skipped (no title/author)"
      return nil
    end

    uri = URI(GOOGLE_BOOKS_URL)
    uri.query = URI.encode_www_form(q: query, maxResults: 3, printType: "books")
    log "google: GET #{uri}"

    response = http_get(uri)
    unless response.is_a?(Net::HTTPSuccess)
      log "google: HTTP #{response.code}"
      return nil
    end

    payload = JSON.parse(response.body)
    total = Array(payload["items"]).size
    item = Array(payload["items"]).find { |i| i.dig("volumeInfo", "imageLinks") }
    unless item
      log "google: #{total} result(s), none with cover"
      return nil
    end

    info = item["volumeInfo"]
    thumb = info.dig("imageLinks", "thumbnail") || info.dig("imageLinks", "smallThumbnail")
    unless thumb
      log "google: item has imageLinks but no thumbnail"
      return nil
    end

    # Google returns zoom=1 + curl edges by default. Bump to zoom=2, drop curl,
    # force https so ActiveStorage can store it without mixed-content warnings.
    url = thumb.sub("&edge=curl", "").sub("&zoom=1", "&zoom=2").sub(/\Ahttp:/, "https:")
    isbn_ids = Array(info["industryIdentifiers"])
    isbn = isbn_ids.find { |id| id["type"] == "ISBN_13" }&.dig("identifier") ||
      isbn_ids.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")

    log "google: matched \"#{info["title"]}\" by #{Array(info["authors"]).join(", ")} → thumb=#{url} isbn=#{isbn.inspect}"
    {url: url, isbn: isbn}
  rescue JSON::ParserError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    log "google: #{e.class}: #{e.message}", level: :warn
    nil
  end

  def open_library_url(isbn)
    "#{OPEN_LIBRARY_COVERS}/#{URI.encode_www_form_component(isbn)}-L.jpg"
  end

  def download_and_attach(url, source:)
    uri = URI(url)
    log "#{source}: downloading #{uri}"
    response = http_get(uri)
    unless response.is_a?(Net::HTTPSuccess)
      log "#{source}: HTTP #{response.code}"
      return false
    end

    body = response.body.to_s
    # Open Library returns a 1×1 placeholder when the cover is missing.
    if body.bytesize < 2_000
      log "#{source}: body too small (#{body.bytesize}B) — treating as missing"
      return false
    end

    content_type = response["content-type"].to_s.split(";").first
    unless content_type&.start_with?("image/")
      log "#{source}: unexpected content-type #{content_type.inspect}"
      return false
    end

    @book.cover_image.attach(
      io: StringIO.new(body),
      filename: "cover-#{source}-#{@book.id}.jpg",
      content_type: content_type
    )
    log "#{source}: attached #{body.bytesize}B (#{content_type})"
    true
  rescue Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    log "#{source}: #{e.class}: #{e.message}", level: :warn
    false
  end

  def build_query
    parts = []
    parts << "intitle:#{@book.title.gsub(/[^\w\s]/, " ")}" if @book.title.present?
    parts << "inauthor:#{@book.author.gsub(/[^\w\s]/, " ")}" if @book.author.present?
    return nil if parts.empty?
    parts.join("+")
  end

  def http_get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req["User-Agent"] = USER_AGENT
      http.request(req)
    end
  end

  def log(message, level: :info)
    Rails.logger.public_send(level, "#{LOG_TAG} #{message}")
  end
end

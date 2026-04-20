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

  def self.call(...) = new(...).call

  def initialize(book)
    @book = book
  end

  def call
    return :already_attached if @book.cover_image.attached?

    google = fetch_google
    if google && download_and_attach(google[:url], source: "google_books")
      @book.update(isbn: google[:isbn]) if google[:isbn].present? && @book.isbn.blank?
      return :google_books
    end

    isbn = @book.isbn.presence || google&.[](:isbn)
    if isbn.present? && download_and_attach(open_library_url(isbn), source: "open_library")
      @book.update(isbn: isbn) if @book.isbn.blank?
      return :open_library
    end

    :none
  end

  private

  def fetch_google
    query = build_query
    return nil unless query

    uri = URI(GOOGLE_BOOKS_URL)
    uri.query = URI.encode_www_form(q: query, maxResults: 3, printType: "books")
    response = http_get(uri)
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    item = Array(payload["items"]).find { |i| i.dig("volumeInfo", "imageLinks") }
    return nil unless item

    info = item["volumeInfo"]
    thumb = info.dig("imageLinks", "thumbnail") || info.dig("imageLinks", "smallThumbnail")
    return nil unless thumb

    # Google returns zoom=1 + curl edges by default. Bump to zoom=2, drop curl,
    # force https so ActiveStorage can store it without mixed-content warnings.
    url = thumb.sub("&edge=curl", "").sub("&zoom=1", "&zoom=2").sub(/\Ahttp:/, "https:")
    isbn_ids = Array(info["industryIdentifiers"])
    isbn = isbn_ids.find { |id| id["type"] == "ISBN_13" }&.dig("identifier") ||
      isbn_ids.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")

    {url: url, isbn: isbn}
  rescue JSON::ParserError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    Rails.logger.warn("[BookCoverFetcher] google_books #{e.class}: #{e.message}")
    nil
  end

  def open_library_url(isbn)
    "#{OPEN_LIBRARY_COVERS}/#{URI.encode_www_form_component(isbn)}-L.jpg"
  end

  def download_and_attach(url, source:)
    uri = URI(url)
    response = http_get(uri)
    return false unless response.is_a?(Net::HTTPSuccess)

    body = response.body.to_s
    # Open Library returns a 1×1 placeholder when the cover is missing.
    return false if body.bytesize < 2_000

    content_type = response["content-type"].to_s.split(";").first
    return false unless content_type&.start_with?("image/")

    @book.cover_image.attach(
      io: StringIO.new(body),
      filename: "cover-#{source}-#{@book.id}.jpg",
      content_type: content_type
    )
    true
  rescue Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    Rails.logger.warn("[BookCoverFetcher] download #{e.class}: #{e.message}")
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
end

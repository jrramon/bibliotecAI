require "net/http"
require "json"
require "uri"

# Queries Google Books and returns a small list of Candidate structs the UI
# can present before the user decides which metadata to apply to a book.
class BookCandidates
  Candidate = Struct.new(
    :volume_id, :title, :subtitle, :authors, :publisher, :published_date,
    :description, :thumbnail_url, :isbn_10, :isbn_13, :page_count, :language,
    keyword_init: true
  ) do
    def isbn = isbn_13 || isbn_10
    def year = published_date.to_s[0, 4]
    def author = authors.to_a.join(", ")
    def published_year = year.presence&.to_i
  end

  GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"
  MAX_RESULTS = 5
  TIMEOUT = 8

  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  BROWSER_HEADERS = {
    "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language" => "en-US,en;q=0.9,es;q=0.8",
    "Accept-Encoding" => "identity"
  }.freeze

  def self.call(...) = new(...).call

  def initialize(query, max: MAX_RESULTS)
    @query = query.to_s.strip
    @max = max
  end

  def call
    return [] if @query.blank?

    params = {q: @query, maxResults: @max, printType: "books"}
    api_key = ENV["GOOGLE_BOOKS_API_KEY"].presence
    params[:key] = api_key if api_key

    uri = URI(GOOGLE_BOOKS_URL)
    uri.query = URI.encode_www_form(params)

    response = http_get(uri)
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn "[BookCandidates] #{response.code} for q=#{@query.inspect} " \
        "key=#{api_key ? "present" : "missing"} body=#{response.body.to_s[0, 200].inspect}"
      return []
    end

    payload = JSON.parse(response.body)
    Array(payload["items"]).map { |item| build(item) }.compact
  rescue JSON::ParserError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    Rails.logger.warn("[BookCandidates] #{e.class}: #{e.message}")
    []
  end

  private

  def build(item)
    info = item["volumeInfo"] || {}
    thumb = info.dig("imageLinks", "thumbnail") || info.dig("imageLinks", "smallThumbnail")
    thumb = thumb&.sub("&edge=curl", "")&.sub(/\Ahttp:/, "https:")

    isbn_ids = Array(info["industryIdentifiers"])
    isbn_10 = isbn_ids.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")
    isbn_13 = isbn_ids.find { |id| id["type"] == "ISBN_13" }&.dig("identifier")

    Candidate.new(
      volume_id: item["id"],
      title: info["title"],
      subtitle: info["subtitle"],
      authors: info["authors"],
      publisher: info["publisher"],
      published_date: info["publishedDate"],
      description: info["description"],
      thumbnail_url: thumb,
      isbn_10: isbn_10,
      isbn_13: isbn_13,
      page_count: info["pageCount"],
      language: info["language"]
    )
  end

  def http_get(uri)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
      open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
      req = Net::HTTP::Get.new(uri.request_uri)
      req["User-Agent"] = USER_AGENT
      BROWSER_HEADERS.each { |k, v| req[k] = v }
      http.request(req)
    end
  end
end

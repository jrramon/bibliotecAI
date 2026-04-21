require "net/http"
require "json"
require "uri"
require "digest"

# Fetches a book cover from Google Books (primary) with an Open Library
# fallback via ISBN. Attaches the downloaded image to `book.cover_image`
# and opportunistically fills in `isbn` if Google returned one.
#
# Both APIs are public, no API key required, free at our expected volume.
class BookCoverFetcher
  # SHA-256 of the "image not available" placeholder Google Books serves
  # when it knows about a volume but has no real cover for it. We download
  # it as a regular 15 KB PNG otherwise, so size alone isn't enough — the
  # hash of the known bytes is.
  PLACEHOLDER_HASHES = %w[
    12557f8948b8bdc6af436e3a8b3adddd45f7f7d2b67c5832e799cdf4686f72bb
  ].freeze

  GOOGLE_BOOKS_URL = "https://www.googleapis.com/books/v1/volumes"
  OPEN_LIBRARY_COVERS = "https://covers.openlibrary.org/b/isbn"
  TIMEOUT = 8
  # Google Books 503s unauthenticated clients that look like bots (our old
  # "BibliotecAI/1.0" UA triggered that). Pose as Chrome, add the Accept
  # headers every browser sends, and retry transient 5xx once.
  USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 " \
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  BROWSER_HEADERS = {
    "Accept" => "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
    "Accept-Language" => "en-US,en;q=0.9,es;q=0.8",
    "Accept-Encoding" => "identity",
    "Cache-Control" => "no-cache",
    "Pragma" => "no-cache"
  }.freeze
  MAX_RETRIES = 2
  LOG_TAG = "[BookCoverFetcher]"

  def self.call(...) = new(...).call

  def initialize(book)
    @book = book
  end

  def call
    log "book ##{@book.id} \"#{@book.title}\" / #{@book.author.presence || "(no author)"}"

    has_cover = @book.cover_image.attached?
    needs_metadata = metadata_blank?
    if has_cover && !needs_metadata
      log "already has cover and metadata, skipping"
      return :already_attached
    end

    google = fetch_google
    if google
      enrich_from_google(google) if needs_metadata

      if !has_cover
        Array(google[:urls]).each do |url|
          next unless download_and_attach(url, source: "google_books")
          log "✓ cover attached from google_books (isbn=#{google[:isbn].inspect})"
          return :google_books
        end
      end
    end

    return :already_attached if has_cover

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

  def metadata_blank?
    @book.publisher.blank? || @book.published_year.blank? || @book.synopsis.blank?
  end

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

    # Google's default thumbnail has `edge=curl` (page-curl effect) and
    # `zoom=1` (≈128×192). Drop the curl effect and force https. We try
    # zoom=2 first (≈256×384) and fall back to zoom=1 because older scans
    # often only ship the small one — the larger size returns a 334-byte
    # placeholder for those books.
    base_url = thumb.sub("&edge=curl", "").sub(/\Ahttp:/, "https:")
    urls = [base_url.sub("&zoom=1", "&zoom=2"), base_url].uniq
    isbn_ids = Array(info["industryIdentifiers"])
    isbn = isbn_ids.find { |id| id["type"] == "ISBN_13" }&.dig("identifier") ||
      isbn_ids.find { |id| id["type"] == "ISBN_10" }&.dig("identifier")

    log "google: matched \"#{info["title"]}\" by #{Array(info["authors"]).join(", ")} → thumbs=#{urls.inspect} isbn=#{isbn.inspect}"
    {
      urls: urls,
      isbn: isbn,
      volume_id: item["id"],
      subtitle: info["subtitle"],
      publisher: info["publisher"],
      published_year: info["publishedDate"].to_s[0, 4].presence&.to_i,
      page_count: info["pageCount"],
      language: info["language"],
      synopsis: info["description"]
    }
  rescue JSON::ParserError, Net::ReadTimeout, Net::OpenTimeout, SocketError => e
    log "google: #{e.class}: #{e.message}", level: :warn
    nil
  end

  def open_library_url(isbn)
    "#{OPEN_LIBRARY_COVERS}/#{URI.encode_www_form_component(isbn)}-L.jpg"
  end

  # Fills any blank metadata fields on the Book with whatever Google returned
  # alongside the cover — never overwrites a non-blank column.
  def enrich_from_google(data)
    updates = {}
    updates[:isbn] = data[:isbn] if data[:isbn].present? && @book.isbn.blank?
    updates[:google_books_id] = data[:volume_id] if data[:volume_id].present? && @book.google_books_id.blank?
    updates[:subtitle] = data[:subtitle] if data[:subtitle].present? && @book.subtitle.blank?
    updates[:publisher] = data[:publisher] if data[:publisher].present? && @book.publisher.blank?
    updates[:published_year] = data[:published_year] if data[:published_year].present? && @book.published_year.blank?
    updates[:page_count] = data[:page_count] if data[:page_count].present? && @book.page_count.blank?
    updates[:language] = data[:language] if data[:language].present? && @book.language.blank?
    updates[:synopsis] = data[:synopsis] if data[:synopsis].present? && @book.synopsis.blank?
    @book.update(updates) if updates.any?
    log "enriched #{updates.keys.inspect}" if updates.any?
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

    hash = Digest::SHA256.hexdigest(body)
    if PLACEHOLDER_HASHES.include?(hash)
      log "#{source}: served the known \"image not available\" placeholder (#{body.bytesize}B, sha=#{hash[0, 12]}…)"
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

  def http_get(uri, accept: nil, retries: MAX_RETRIES)
    response = nil
    (retries + 1).times do |attempt|
      begin
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
          open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
          req = Net::HTTP::Get.new(uri.request_uri)
          req["User-Agent"] = USER_AGENT
          BROWSER_HEADERS.each { |k, v| req[k] = v }
          req["Accept"] = accept if accept
          http.request(req)
        end
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        if attempt < retries
          log "#{e.class} from #{uri.host} (attempt #{attempt + 1}/#{retries + 1}), retrying…", level: :warn
          sleep(0.4 * (attempt + 1))
          next
        end
        raise
      end

      if response.is_a?(Net::HTTPServiceUnavailable) && attempt < retries
        log "HTTP 503 from #{uri.host} (attempt #{attempt + 1}/#{retries + 1}), retrying…", level: :warn
        sleep(0.4 * (attempt + 1))
        next
      end

      break
    end
    response
  end

  def log(message, level: :info)
    Rails.logger.public_send(level, "#{LOG_TAG} #{message}")
  end
end

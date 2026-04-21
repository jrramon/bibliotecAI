class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_book, only: %i[show edit update destroy fetch_cover candidates apply_candidate note start_reading finish_reading stop_reading]

  def show
  end

  def fetch_cover
    result = BookCoverFetcher.call(@book)
    redirect_to [@library, @book], **cover_flash(result)
  rescue => e
    Rails.logger.warn("[BooksController#fetch_cover] #{e.class}: #{e.message}")
    redirect_to [@library, @book], alert: "Error al buscar portada: #{e.message}"
  end

  def new
    @book = @library.books.build
  end

  def create
    @book = @library.books.build(book_params.merge(added_by_user: current_user))
    if @book.save
      redirect_to [@library, @book], notice: "Libro añadido."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @book.update(book_params)
      redirect_to [@library, @book], notice: "Libro actualizado."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def candidates
    @query = params[:q].presence || "#{@book.title} #{@book.author}".strip
    @candidates = BookCandidates.call(@query)
    render partial: "books/candidates", locals: {candidates: @candidates, query: @query, book: @book}
  end

  def note
    n = @book.note_for(current_user)
    n.body = params.dig(:user_book_note, :body).to_s
    n.save!
    redirect_to [@library, @book], notice: n.body.blank? ? "Nota borrada." : "Nota guardada."
  end

  def start_reading
    status = @book.reading_statuses.find_or_initialize_by(user: current_user)
    status.state = :reading
    status.started_at ||= Time.current
    status.finished_at = nil
    status.save!
    redirect_to [@library, @book], notice: "Marcado como leyendo."
  end

  def finish_reading
    status = @book.reading_statuses.find_or_initialize_by(user: current_user)
    status.state = :read
    status.started_at ||= Time.current
    status.finished_at = Time.current
    status.save!
    redirect_to [@library, @book], notice: "¡Marcado como leído!"
  end

  def stop_reading
    status = @book.reading_statuses.find_by(user: current_user)
    status&.destroy
    redirect_to [@library, @book], notice: "Estado de lectura eliminado."
  end

  def apply_candidate
    data = params.require(:candidate).permit(
      :title, :subtitle, :author, :isbn, :publisher, :published_date, :published_year,
      :page_count, :language, :synopsis, :google_books_id, :thumbnail_url
    )

    # Full replacement of the Google-Books-backed fields: if a field is
    # missing from the new candidate we clear it (nil-ify) rather than
    # leave the previous candidate's value lingering. Fields NOT managed by
    # Google Books (cdu, genres, goodreads_url, user notes) stay untouched.
    updates = {
      title: data[:title].presence || @book.title,   # keep existing if candidate has none
      subtitle: data[:subtitle].presence,
      author: data[:author].presence,
      publisher: data[:publisher].presence,
      isbn: data[:isbn].presence,
      synopsis: data[:synopsis].presence,
      language: data[:language].presence,
      google_books_id: data[:google_books_id].presence
    }
    year = (data[:published_year].presence || data[:published_date].to_s[0, 4]).to_i
    updates[:published_year] = (year > 0) ? year : nil
    pages = data[:page_count].to_i
    updates[:page_count] = (pages > 0) ? pages : nil

    unless @book.update(updates)
      Rails.logger.warn "[apply_candidate] update failed for ##{@book.id}: #{@book.errors.full_messages.to_sentence}"
      return redirect_to edit_library_book_path(@library, @book),
        alert: "No se pudieron aplicar los datos: #{@book.errors.full_messages.to_sentence}"
    end

    # Always replace the cover too: if the new candidate has a thumbnail
    # use it; otherwise drop the previous one so the book clearly reflects
    # the new selection instead of keeping a wrong cover from an earlier try.
    @book.cover_image.purge if @book.cover_image.attached?
    if data[:thumbnail_url].present?
      attach_remote_cover(data[:thumbnail_url])
    end

    redirect_to [@library, @book], notice: "Datos aplicados desde Google Books."
  rescue => e
    Rails.logger.warn("[BooksController#apply_candidate] #{e.class}: #{e.message}")
    redirect_to edit_library_book_path(@library, @book), alert: "No se pudo aplicar el candidato."
  end

  def destroy
    @book.destroy
    redirect_to library_path(@library), notice: "Libro eliminado."
  end

  private

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end

  def set_book
    @book = @library.books.friendly.find(params[:id])
  end

  def book_params
    # :notes stays out of the permitted list — personal notes are per-user now,
    # edited via #note and stored in user_book_notes.
    permitted = params.expect(book: [
      :title, :subtitle, :author, :publisher, :published_year, :page_count, :language,
      :isbn, :goodreads_url, :synopsis, :cover_image, :cdu, :stamp, :spine_palette, :genres_csv
    ])
    if permitted[:genres_csv]
      permitted[:genres] = permitted.delete(:genres_csv).to_s.split(",").map(&:strip).reject(&:empty?)
    end
    permitted
  end

  def cover_flash(result)
    case result
    when :google_books then {notice: "Portada encontrada en Google Books."}
    when :open_library then {notice: "Portada encontrada en Open Library."}
    when :already_attached then {notice: "Ya tenía portada."}
    else {alert: "No se encontró portada."}
    end
  end

  # Tries both zoom=2 and zoom=1 variants (same logic as BookCoverFetcher)
  # so user-picked candidates also recover from the 334-byte placeholder case.
  # Logs each attempt so failures are visible in log/development.log via
  # `grep CoverApply`.
  def attach_remote_cover(url)
    base = url.sub("&edge=curl", "").sub(/\Ahttp:/, "https:")
    urls = [base.sub("&zoom=1", "&zoom=2"), base].uniq
    Rails.logger.info "[CoverApply] book ##{@book.id} trying #{urls.size} urls"

    urls.each do |candidate_url|
      uri = URI(candidate_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: 8) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = BookCandidates::USER_AGENT
        BookCandidates::BROWSER_HEADERS.each { |k, v| req[k] = v }
        http.request(req)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.info "[CoverApply] #{candidate_url} → HTTP #{response.code}"
        next
      end

      body = response.body.to_s
      if body.bytesize < 2_000
        Rails.logger.info "[CoverApply] #{candidate_url} → too small (#{body.bytesize}B)"
        next
      end

      if BookCoverFetcher::PLACEHOLDER_HASHES.include?(Digest::SHA256.hexdigest(body))
        Rails.logger.info "[CoverApply] #{candidate_url} → known placeholder"
        next
      end

      unless BookCoverFetcher.plausible_cover?(body)
        dims = BookCoverFetcher.sniff_dimensions(body)
        Rails.logger.info "[CoverApply] #{candidate_url} → implausible dims=#{dims.inspect}"
        next
      end

      content_type = response["content-type"].to_s.split(";").first
      unless content_type&.start_with?("image/")
        Rails.logger.info "[CoverApply] #{candidate_url} → unexpected content-type #{content_type.inspect}"
        next
      end

      @book.cover_image.purge if @book.cover_image.attached?
      @book.cover_image.attach(io: StringIO.new(body), filename: "cover-chosen-#{@book.id}.jpg", content_type: content_type)
      Rails.logger.info "[CoverApply] ✓ attached #{body.bytesize}B (#{content_type}) from #{candidate_url}"
      return true
    end

    Rails.logger.warn "[CoverApply] ✗ no usable cover for book ##{@book.id}"
    false
  end
end

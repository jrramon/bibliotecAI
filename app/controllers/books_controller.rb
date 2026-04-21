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
    cover_photo_id = params.dig(:book, :cover_photo_id).presence
    if @book.save
      attach_cover_from_photo(@book, cover_photo_id) if cover_photo_id
      respond_to do |format|
        format.turbo_stream { render :shelved }
        format.html { redirect_to [@library, @book], notice: "Libro añadido." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "new-book-form",
            partial: "books/new_modal_form",
            locals: {library: @library, book: @book}
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_entity }
      end
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

  # Each start is a new reading attempt; previous attempts (read / dropped)
  # are preserved as history. If there's already an active :reading, we
  # don't create a duplicate.
  def start_reading
    active = @book.reading_statuses.active.find_by(user: current_user)
    if active
      redirect_to [@library, @book], notice: "Ya estás leyendo este libro."
    else
      @book.reading_statuses.create!(user: current_user, state: :reading, started_at: Time.current)
      past = @book.completed_reads_for(current_user).count
      msg = past.zero? ? "Marcado como leyendo." : "Releyendo (vez #{past + 1})."
      redirect_to [@library, @book], notice: msg
    end
  end

  # Accepts `finished_on` as:
  # - nil / missing  → today
  # - "none"         → finished_at is nil (read long ago, date unknown)
  # - an ISO date    → that date
  def finish_reading
    finished_at = parse_finished_on(params[:finished_on])
    active = @book.reading_statuses.active.find_by(user: current_user)
    if active
      active.update!(state: :read, finished_at: finished_at)
    else
      @book.reading_statuses.create!(user: current_user, state: :read,
        started_at: nil, finished_at: finished_at)
    end
    redirect_to [@library, @book], notice: finish_notice(finished_at)
  end

  # Marks the current attempt as dropped (not deleted) so the history stays.
  def stop_reading
    active = @book.reading_statuses.active.find_by(user: current_user)
    active&.update!(state: :dropped, finished_at: Time.current)
    redirect_to [@library, @book], notice: "Lectura actual marcada como abandonada."
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

  # When the add-book modal was opened from a cover photo, the user-submitted
  # form carries `book[cover_photo_id]`. Pull that CoverPhoto's uploaded image
  # across so the new book has a cover without a separate upload.
  def attach_cover_from_photo(book, cover_photo_id)
    photo = @library.cover_photos.find_by(id: cover_photo_id)
    return unless photo&.image&.attached?
    blob = photo.image.blob
    book.cover_image.attach(
      io: StringIO.new(blob.download),
      filename: blob.filename.to_s,
      content_type: blob.content_type
    )
  rescue => e
    Rails.logger.warn("[BooksController#attach_cover_from_photo] #{e.class}: #{e.message}")
  end

  def parse_finished_on(raw)
    return nil if raw.to_s == "none"
    return Time.current if raw.blank?
    Date.iso8601(raw.to_s).to_time
  rescue ArgumentError
    Time.current
  end

  def finish_notice(finished_at)
    return "Marcado como leído (sin fecha)." if finished_at.nil?
    return "¡Marcado como leído!" if finished_at.to_date == Date.current
    "Marcado como leído · #{I18n.l(finished_at.to_date, format: :long)}."
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

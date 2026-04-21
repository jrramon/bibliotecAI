class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_book, only: %i[show edit update destroy fetch_cover candidates apply_candidate note]

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

  def apply_candidate
    data = params.require(:candidate).permit(
      :title, :subtitle, :author, :isbn, :publisher, :published_date, :published_year,
      :page_count, :language, :synopsis, :google_books_id, :thumbnail_url
    )

    updates = {}
    %i[title subtitle author publisher isbn synopsis language google_books_id].each do |key|
      updates[key] = data[key] if data[key].present?
    end
    updates[:published_year] = data[:published_year].to_i if data[:published_year].present?
    updates[:published_year] ||= data[:published_date].to_s[0, 4].to_i if data[:published_date].to_s[0, 4].present? && data[:published_date].to_s[0, 4].to_i > 0
    updates[:page_count] = data[:page_count].to_i if data[:page_count].present?

    @book.update(updates) if updates.any?

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
      :isbn, :goodreads_url, :synopsis, :cover_image, :cdu, :genres_csv
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
  def attach_remote_cover(url)
    base = url.sub("&edge=curl", "").sub(/\Ahttp:/, "https:")
    urls = [base.sub("&zoom=1", "&zoom=2"), base].uniq
    urls.each do |candidate_url|
      uri = URI(candidate_url)
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 8, read_timeout: 8) do |http|
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = BookCandidates::USER_AGENT
        BookCandidates::BROWSER_HEADERS.each { |k, v| req[k] = v }
        http.request(req)
      end
      next unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s
      next if body.bytesize < 2_000
      content_type = response["content-type"].to_s.split(";").first
      next unless content_type&.start_with?("image/")

      @book.cover_image.purge if @book.cover_image.attached?
      @book.cover_image.attach(io: StringIO.new(body), filename: "cover-chosen-#{@book.id}.jpg", content_type: content_type)
      break
    end
  end
end

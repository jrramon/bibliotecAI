class CoverPhotosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library

  def create
    @cover_photo = @library.cover_photos.build(
      uploaded_by_user: current_user,
      image: params.require(:image)
    )

    if @cover_photo.save
      # Processed by the host `bin/shelf-photo-poller` (which can reach the
      # local Claude CLI). No ActiveJob enqueue here — the web container
      # has no `claude` binary on its PATH.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "new-book-form",
            partial: "cover_photos/analyzing",
            locals: {library: @library, cover_photo: @cover_photo, book: @library.books.build}
          )
        end
        format.html { redirect_to library_path(@library) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "new-book-form",
            partial: "books/new_modal_form",
            locals: {library: @library, book: @library.books.build.tap { |b|
              @cover_photo.errors.full_messages.each { |msg| b.errors.add(:base, msg) }
            }}
          ), status: :unprocessable_entity
        end
      end
    end
  end

  private

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end
end

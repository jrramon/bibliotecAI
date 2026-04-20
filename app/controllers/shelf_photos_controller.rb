class ShelfPhotosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_shelf_photo, only: %i[show]

  def new
    @shelf_photo = @library.shelf_photos.build
  end

  def create
    @shelf_photo = @library.shelf_photos.build(uploaded_by_user: current_user, image: params.dig(:shelf_photo, :image))
    if @shelf_photo.save
      # The host-side `bin/shelf-photo-poller` picks this up and shells
      # out to the local Claude CLI. No ActiveJob enqueue — the Rails
      # web process can't reach the host-installed claude binary.
      redirect_to [@library, @shelf_photo], notice: "Foto subida. Identificando libros…"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end

  private

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end

  def set_shelf_photo
    @shelf_photo = @library.shelf_photos.find(params[:id])
  end
end

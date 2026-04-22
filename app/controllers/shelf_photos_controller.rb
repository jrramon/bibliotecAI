class ShelfPhotosController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_shelf_photo, only: %i[show]

  def new
    @shelf_photo = @library.shelf_photos.build
  end

  # Accepts either a single `shelf_photo[image]` upload (legacy / single-file
  # path) or a multi-select `shelf_photo[images][]` array. Each uploaded
  # image becomes its own ShelfPhoto row in :pending state; the host-side
  # poller drains them one at a time (it shells out to `claude -p`, which
  # serialises anyway), so this works as a natural queue without any job
  # backend.
  def create
    images = uploaded_images
    if images.empty?
      @shelf_photo = @library.shelf_photos.build
      @shelf_photo.errors.add(:image, "es obligatoria")
      return render :new, status: :unprocessable_entity
    end

    created = []
    failed = []
    images.each do |file|
      photo = @library.shelf_photos.build(uploaded_by_user: current_user, image: file)
      if photo.save
        created << photo
      else
        failed << [file.respond_to?(:original_filename) ? file.original_filename : "imagen", photo.errors.full_messages]
      end
    end

    if created.empty?
      @shelf_photo = @library.shelf_photos.build
      failed.each { |name, errs| @shelf_photo.errors.add(:base, "#{name}: #{errs.to_sentence}") }
      render :new, status: :unprocessable_entity
    elsif created.size == 1 && failed.empty?
      redirect_to [@library, created.first], notice: "Foto subida. Identificando libros…"
    else
      notice = pluralize(created.size, "foto subida", plural: "fotos subidas") + " · en cola para identificar."
      if failed.any?
        notice += " #{pluralize(failed.size, "fallo")}: #{failed.map(&:first).to_sentence}."
      end
      redirect_to library_path(@library), notice: notice
    end
  end

  def show
  end

  private

  def uploaded_images
    Array(params.dig(:shelf_photo, :images)).compact_blank +
      Array(params.dig(:shelf_photo, :image)).compact_blank
  end

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end

  def set_shelf_photo
    @shelf_photo = @library.shelf_photos.find(params[:id])
  end

  def pluralize(...)
    ActionController::Base.helpers.pluralize(...)
  end
end

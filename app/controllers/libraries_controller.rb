class LibrariesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library, only: %i[show settings]

  def index
    @libraries = current_user.libraries.order(:name)
  end

  def show
    @query = params[:q].to_s.strip
    @books = Book.search_in_library(@library, query: @query, viewer: current_user).recent
    @reading_books = current_user.reading_statuses.active.for_library(@library).includes(:book).map(&:book) if @query.blank?
  end

  def settings
    @is_owner = membership&.owner?
  end

  def new
    @library = current_user.owned_libraries.build
  end

  def create
    @library = current_user.owned_libraries.build(library_params)
    if @library.save
      redirect_to @library, notice: "Biblioteca creada."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def membership
    current_user.memberships.find_by(library: @library)
  end

  def set_library
    @library = current_user.libraries.friendly.find(params[:id])
  end

  def library_params
    params.expect(library: [:name, :description])
  end
end

class BooksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_book, only: %i[show edit update destroy]

  def index
    @books = @library.books.recent
  end

  def show
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

  def destroy
    @book.destroy
    redirect_to library_books_path(@library), notice: "Libro eliminado."
  end

  private

  def set_library
    @library = current_user.libraries.friendly.find(params[:library_id])
  end

  def set_book
    @book = @library.books.friendly.find(params[:id])
  end

  def book_params
    params.expect(book: [:title, :author, :isbn, :goodreads_url, :notes, :cover_image])
  end
end

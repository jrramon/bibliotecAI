class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library_and_book
  before_action :set_comment, only: %i[destroy]

  def create
    @comment = @book.comments.build(comment_params.merge(user: current_user))
    if @comment.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to [@library, @book], notice: "Comentario publicado." }
      end
    else
      redirect_to [@library, @book], alert: "No se pudo publicar el comentario."
    end
  end

  def destroy
    if @comment.user_id == current_user.id
      @comment.destroy
    end
    redirect_to [@library, @book]
  end

  private

  def set_library_and_book
    @library = current_user.libraries.friendly.find(params[:library_id])
    @book = @library.books.friendly.find(params[:book_id])
  end

  def set_comment
    @comment = @book.comments.find(params[:id])
  end

  def comment_params
    params.expect(comment: [:body])
  end
end

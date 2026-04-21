class ReadingStatusesController < ApplicationController
  before_action :authenticate_user!

  def destroy
    library = current_user.libraries.friendly.find(params[:library_id])
    book = library.books.friendly.find(params[:book_id])
    status = book.reading_statuses.where(user: current_user).find(params[:id])
    status.destroy!
    redirect_to [library, book], notice: "Entrada del historial borrada."
  end
end

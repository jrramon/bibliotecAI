class SearchController < ApplicationController
  before_action :authenticate_user!

  def show
    @query = params[:q].to_s.strip
    @books = Book.search_for_viewer(@query, viewer: current_user)
    @members = User.search_within_viewer_libraries(@query, viewer: current_user)
    @notes = UserBookNote.search_for_viewer(@query, viewer: current_user)

    respond_to do |format|
      format.html { render layout: false if turbo_frame_request? }
      format.turbo_stream
    end
  end
end

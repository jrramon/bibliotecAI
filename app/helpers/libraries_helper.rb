module LibrariesHelper
  # Builds the path for a genre chip on libraries#show, preserving the
  # active search query and sort (when non-default) and toggling the
  # genre filter on/off.
  def library_genre_chip_path(library, genre:, query:, sort:)
    params = {}
    params[:genre] = genre if genre
    params[:q] = query if query.present?
    params[:sort] = sort if sort && sort != "recent"
    library_path(library, params)
  end
end

module Mcp
  module Tools
    # Searches every library the user belongs to (Book.search_for_viewer
    # already enforces that scope) for books whose title, author, or
    # synopsis matches `query`. Out-of-range `limit` values are clamped
    # rather than rejected — easier on the model.
    class SearchBooks < Mcp::Tool
      NAME = "search_books"
      DESCRIPTION = "Busca libros en las bibliotecas del usuario por título, autor o sinopsis. Devuelve hasta `limit` resultados."
      DEFAULT_LIMIT = 5
      MAX_LIMIT = 20

      INPUT_SCHEMA = {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "Texto a buscar (título, autor, palabra de la sinopsis)."
          },
          limit: {
            type: "integer",
            minimum: 1,
            maximum: MAX_LIMIT,
            description: "Número máximo de resultados (1-#{MAX_LIMIT}). Por defecto #{DEFAULT_LIMIT}."
          }
        },
        required: ["query"],
        additionalProperties: false
      }.freeze

      def call
        query = @arguments["query"].to_s.strip
        raise ArgumentError, "query is required" if query.empty?

        limit = clamp_limit(@arguments["limit"])

        Book.search_for_viewer(query, viewer: @user, limit: limit).map do |book|
          {
            book_id: book.id,
            title: book.title,
            author: book.author,
            published_year: book.published_year,
            library_id: book.library_id,
            library: book.library.name
          }
        end
      end

      private

      def clamp_limit(raw)
        return DEFAULT_LIMIT if raw.nil?
        n = raw.to_i
        return DEFAULT_LIMIT if n <= 0
        [n, MAX_LIMIT].min
      end
    end
  end
end

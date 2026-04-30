module Mcp
  module Tools
    # Returns the user's wishlist, most-recent first. The model already
    # caps note/title length at the validation layer, so we don't truncate
    # again here.
    class ListMyWishlist < Mcp::Tool
      NAME = "list_my_wishlist"
      DESCRIPTION = "Devuelve los libros que el usuario tiene apuntados en su wishlist (lista de deseos), del más reciente al más antiguo."
      DEFAULT_LIMIT = 20
      MAX_LIMIT = 50

      INPUT_SCHEMA = {
        type: "object",
        properties: {
          limit: {
            type: "integer",
            minimum: 1,
            maximum: MAX_LIMIT,
            description: "Número máximo de items (1-#{MAX_LIMIT}). Por defecto #{DEFAULT_LIMIT}."
          }
        },
        additionalProperties: false
      }.freeze

      def call
        limit = clamp_limit(@arguments["limit"])

        @user.wishlist_items.recent.limit(limit).map do |item|
          {
            item_id: item.id,
            title: item.title,
            author: item.author,
            isbn: item.isbn,
            note: item.note
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

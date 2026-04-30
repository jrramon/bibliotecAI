module Mcp
  module Tools
    # Adds a book to the user's wishlist. Dedupes against existing items
    # via WishlistItem.match_for (the same matcher Book uses to prune
    # wishlist entries when a book is added). On dedupe we don't create
    # a new row — we return the existing one with `deduped: true` so
    # Claude can phrase «ya estaba apuntado» without the user noticing
    # internal mechanics.
    class AddToWishlist < Mcp::Tool
      NAME = "add_to_wishlist"
      DESCRIPTION = "Añade un libro a la wishlist (lista de deseos) del usuario. Si ya hay un item con el mismo título y autor (o el mismo ISBN) lo detecta y no duplica."

      INPUT_SCHEMA = {
        type: "object",
        properties: {
          title: {type: "string", description: "Título del libro (obligatorio)."},
          author: {type: "string", description: "Autor."},
          isbn: {type: "string", description: "ISBN si se conoce."},
          note: {type: "string", description: "Nota corta opcional."}
        },
        required: ["title"],
        additionalProperties: false
      }.freeze

      def call
        title = @arguments["title"].to_s.strip
        raise ArgumentError, "title is required" if title.empty?

        author = @arguments["author"].to_s.strip.presence
        isbn = @arguments["isbn"].to_s.strip.presence
        note = @arguments["note"].to_s.strip.presence

        existing = WishlistItem.match_for(title: title, author: author, user: @user, isbn: isbn).first
        if existing
          return {
            ok: true,
            item_id: existing.id,
            deduped: true,
            title: existing.title,
            author: existing.author
          }
        end

        item = @user.wishlist_items.create!(
          title: title,
          author: author,
          isbn: isbn,
          note: note
        )

        {
          ok: true,
          item_id: item.id,
          deduped: false,
          title: item.title,
          author: item.author
        }
      end
    end
  end
end

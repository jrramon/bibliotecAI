module Mcp
  module Tools
    # Removes one of the user's own wishlist items by id. The lookup is
    # `@user.wishlist_items.find_by(id:)` — items belonging to other
    # users return :not_found and can never be touched. That's the
    # entire cross-user-leak defense.
    class RemoveFromWishlist < Mcp::Tool
      NAME = "remove_from_wishlist"
      DESCRIPTION = "Elimina un item de la wishlist del usuario por su id. Devuelve {ok: false, error: 'not found'} si el item no existe o no pertenece al usuario."

      INPUT_SCHEMA = {
        type: "object",
        properties: {
          item_id: {
            type: "integer",
            description: "Id del WishlistItem (lo devuelve list_my_wishlist como `item_id`)."
          }
        },
        required: ["item_id"],
        additionalProperties: false
      }.freeze

      def call
        raw = @arguments["item_id"]
        raise ArgumentError, "item_id is required" if raw.nil?

        id = raw.to_i
        raise ArgumentError, "item_id must be a positive integer" if id <= 0

        item = @user.wishlist_items.find_by(id: id)
        return {ok: false, error: "not found"} unless item

        title = item.title
        item.destroy!

        {ok: true, item_id: id, title: title}
      end
    end
  end
end

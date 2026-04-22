# Public read-only view of a user's wishlist. Anyone with the token
# link sees it — NO auth required. Tokens are nil by default (private)
# and are generated only when the owner explicitly enables sharing.
class PublicWishlistsController < ApplicationController
  layout "public"

  def show
    @owner = User.find_by(wishlist_share_token: params[:token])
    return render_not_found unless @owner

    @items = @owner.wishlist_items.recent
  end

  private

  def render_not_found
    render plain: "Lista no encontrada", status: :not_found, layout: false
  end
end

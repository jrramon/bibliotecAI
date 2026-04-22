class WishlistItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_item, only: %i[update destroy]

  def index
    @items = current_user.wishlist_items.recent
    @query = params[:q].to_s.strip
    @candidates = @query.present? ? BookCandidates.call(@query) : []
  end

  def create
    @item = current_user.wishlist_items.build(item_params)
    if @item.save
      redirect_to wishlist_items_path, notice: "Añadido a tu lista de deseos."
    else
      @items = current_user.wishlist_items.recent
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @item.update(item_params)
      redirect_to wishlist_items_path, notice: "Lista actualizada."
    else
      @items = current_user.wishlist_items.recent
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @item.destroy
    redirect_to wishlist_items_path, notice: "Eliminado de tu lista de deseos."
  end

  private

  def set_item
    @item = current_user.wishlist_items.find(params[:id])
  end

  def item_params
    params.require(:wishlist_item).permit(
      :title, :author, :isbn, :note, :google_books_id, :thumbnail_url
    )
  end
end

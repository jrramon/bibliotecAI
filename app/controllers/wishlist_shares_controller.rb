class WishlistSharesController < ApplicationController
  before_action :authenticate_user!

  # Toggle — enable (generate token), rotate (generate new one), or
  # disable (null out). The action driven by a hidden `commit` param on
  # the form so one controller handles all three buttons.
  def update
    case params[:commit_action]
    when "enable", "rotate"
      current_user.regenerate_wishlist_share_token!
      notice = (params[:commit_action] == "enable") ? "Link público generado." : "Nuevo link — el anterior deja de funcionar."
    when "disable"
      current_user.disable_wishlist_sharing!
      notice = "Ya no es pública."
    else
      return redirect_to wishlist_path
    end

    redirect_to wishlist_path, notice: notice
  end
end

Rails.application.routes.draw do
  devise_for :users, controllers: {registrations: "users/registrations"}
  get "up" => "rails/health#show", :as => :rails_health_check

  # PWA manifest + service worker. Served at the root so the browser
  # finds them at their conventional paths.
  get "manifest.json", to: "pwa#manifest", as: :pwa_manifest
  get "service-worker.js", to: "pwa#service_worker", as: :pwa_service_worker

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Telegram bot webhook. The path includes a secret segment that must match
  # ENV["TELEGRAM_WEBHOOK_SECRET"] — Telegram POSTs `update` payloads here.
  # See docs/telegram-bot.md for the BotFather + setWebhook flow.
  post "/telegram/webhook/:secret", to: "telegram/webhooks#create", as: :telegram_webhook

  resources :libraries, only: %i[index show new create] do
    member do
      get :settings
    end
    resources :invitations, only: %i[create destroy] do
      member do
        post :resend
      end
    end
    resources :books, except: %i[index] do
      member do
        post :fetch_cover
        get :candidates
        post :apply_candidate
        patch :note
        post :start_reading
        post :finish_reading
        delete :stop_reading
      end
      resources :reading_statuses, only: %i[destroy]
      resources :comments, only: %i[create destroy]
    end
    resources :shelf_photos, only: %i[new create show]
    resources :cover_photos, only: %i[create]
  end

  get "/search", to: "search#show", as: :search
  resources :wishlist_items, only: %i[index create update destroy]
  get "/wishlist", to: "wishlist_items#index", as: :wishlist
  patch "/wishlist/share", to: "wishlist_shares#update", as: :wishlist_share
  get "/w/:token", to: "public_wishlists#show", as: :public_wishlist

  get "invitations/:token", to: "invitations#show", as: :invitation

  authenticated :user do
    root to: "libraries#index", as: :authenticated_root
  end

  root "home#index"
end

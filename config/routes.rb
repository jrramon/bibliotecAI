Rails.application.routes.draw do
  devise_for :users, controllers: {registrations: "users/registrations"}
  get "up" => "rails/health#show", :as => :rails_health_check

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  resources :libraries, only: %i[index show new create] do
    member do
      get :settings
    end
    resources :invitations, only: %i[create]
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
      resources :comments, only: %i[create destroy]
    end
    resources :shelf_photos, only: %i[new create show]
  end

  get "invitations/:token", to: "invitations#show", as: :invitation

  authenticated :user do
    root to: "libraries#index", as: :authenticated_root
  end

  root "home#index"
end

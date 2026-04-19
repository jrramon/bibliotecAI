Rails.application.routes.draw do
  devise_for :users, controllers: {registrations: "users/registrations"}
  get "up" => "rails/health#show", :as => :rails_health_check

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  resources :libraries, only: %i[index show new create] do
    resources :invitations, only: %i[create]
    resources :books
  end

  get "invitations/:token", to: "invitations#show", as: :invitation

  authenticated :user do
    root to: "libraries#index", as: :authenticated_root
  end

  root "home#index"
end

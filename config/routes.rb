Rails.application.routes.draw do
  devise_for :users
  get "up" => "rails/health#show", :as => :rails_health_check

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  root "home#index"
end

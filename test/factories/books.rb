FactoryBot.define do
  factory :book do
    association :library
    association :added_by_user, factory: :user
    sequence(:title) { |n| "Libro #{n}" }
    author { "Autor de prueba" }
  end
end

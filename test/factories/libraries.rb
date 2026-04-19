FactoryBot.define do
  factory :library do
    sequence(:name) { |n| "Biblioteca #{n}" }
    description { "Una biblioteca de prueba." }
    association :owner, factory: :user
  end
end

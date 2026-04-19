FactoryBot.define do
  factory :comment do
    association :book
    association :user
    body { "Un comentario de prueba." }
  end
end

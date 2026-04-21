FactoryBot.define do
  factory :user_book_note do
    user { nil }
    book { nil }
    body { "MyText" }
  end
end

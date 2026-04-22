FactoryBot.define do
  factory :wishlist_item do
    association :user
    sequence(:title) { |n| "Wishlist title #{n}" }
    author { "Test Author" }
  end
end

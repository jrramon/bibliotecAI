FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.test" }
    password { "supersecret123" }
    password_confirmation { "supersecret123" }
  end
end

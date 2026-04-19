FactoryBot.define do
  factory :invitation do
    association :library
    association :invited_by, factory: :user
    sequence(:email) { |n| "invitee#{n}@bibliotecai.test" }
  end
end

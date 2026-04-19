FactoryBot.define do
  factory :membership do
    association :user
    association :library
    role { :member }
  end
end

FactoryBot.define do
  factory :reading_status do
    association :user
    association :book
    state { :reading }
    started_at { Time.current }
  end
end

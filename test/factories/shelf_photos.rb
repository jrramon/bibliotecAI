FactoryBot.define do
  factory :shelf_photo do
    association :library
    association :uploaded_by_user, factory: :user
    status { :pending }

    after(:build) do |photo|
      photo.image.attach(
        io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg")),
        filename: "shelf.jpg",
        content_type: "image/jpeg"
      )
    end
  end
end

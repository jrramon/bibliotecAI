require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "rejects an avatar over 10 MB" do
    user = create(:user)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg")),
      filename: "avatar.jpg",
      content_type: "image/jpeg"
    )
    user.avatar.blob.update!(byte_size: 11.megabytes)
    assert_not user.valid?
    assert_includes user.errors[:avatar], "no debe superar 10 MB"
  end

  test "accepts an avatar at exactly 10 MB" do
    user = create(:user)
    user.avatar.attach(
      io: File.open(Rails.root.join("test/fixtures/files/shelf.jpg")),
      filename: "avatar.jpg",
      content_type: "image/jpeg"
    )
    user.avatar.blob.update!(byte_size: 10.megabytes)
    assert user.valid?
  end
end

require "test_helper"

class CoverPhotoTest < ActiveSupport::TestCase
  test "rejects an image over 10 MB" do
    photo = build(:cover_photo)
    photo.image.blob.update!(byte_size: 11.megabytes)
    assert_not photo.valid?
    assert_includes photo.errors[:image], "no debe superar 10 MB"
  end

  test "accepts an image at exactly 10 MB" do
    photo = build(:cover_photo)
    photo.image.blob.update!(byte_size: 10.megabytes)
    assert photo.valid?
  end
end

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

  test "identified? is true when Claude returned a title" do
    photo = build(:cover_photo)
    photo.claude_raw_response = {"title" => "Kokoro", "confidence" => 0.9}
    assert photo.identified?
  end

  test "identified? is false for an empty Claude result" do
    photo = build(:cover_photo)
    photo.claude_raw_response = {"title" => "", "confidence" => 0}
    assert_not photo.identified?
  end

  test "identified? is false when Claude was never run" do
    photo = build(:cover_photo)
    assert_nil photo.claude_raw_response
    assert_not photo.identified?
  end
end

require "test_helper"

class Eval::FakeShelfPhotoTest < ActiveSupport::TestCase
  setup do
    @path = Rails.root.join("test/fixtures/files/shelf.jpg").to_s
  end

  test "quacks like a ShelfPhoto for the methods ClaudeBookIdentifier touches" do
    fake = Eval::FakeShelfPhoto.new(id: 42, image_path: @path, library_id: 99)

    assert_equal 42, fake.id
    assert_equal 99, fake.library_id
    assert fake.image.attached?
    assert_equal "shelf.jpg", fake.image.filename.to_s
    assert_equal File.binread(@path), fake.image.download
  end

  test "library_id defaults to nil when not given" do
    fake = Eval::FakeShelfPhoto.new(id: 1, image_path: @path)
    assert_nil fake.library_id
  end
end

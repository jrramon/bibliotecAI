require "test_helper"

class Mcp::Tools::ListMyLibrariesTest < ActiveSupport::TestCase
  setup do
    @user = create(:user)
  end

  test "returns owned libraries with book counts" do
    lib1 = create(:library, owner: @user, name: "Casa")
    lib2 = create(:library, owner: @user, name: "Trabajo")
    create(:book, library: lib1)
    create(:book, library: lib1)
    create(:book, library: lib2)

    result = Mcp::Tools::ListMyLibraries.call(user: @user, arguments: {})

    assert_equal 2, result.size
    casa = result.find { |r| r[:name] == "Casa" }
    assert_equal 2, casa[:books_count]
    trabajo = result.find { |r| r[:name] == "Trabajo" }
    assert_equal 1, trabajo[:books_count]
  end

  test "returns libraries the user belongs to as a member, not just owner" do
    owner = create(:user)
    library = create(:library, owner: owner, name: "Compartida")
    create(:membership, user: @user, library: library, role: :member)

    result = Mcp::Tools::ListMyLibraries.call(user: @user, arguments: {})

    assert_equal ["Compartida"], result.map { |r| r[:name] }
  end

  test "returns an empty array when the user has no libraries" do
    result = Mcp::Tools::ListMyLibraries.call(user: @user, arguments: {})
    assert_equal [], result
  end

  test "does not leak libraries belonging to other users" do
    other = create(:user)
    create(:library, owner: other, name: "Ajena")

    result = Mcp::Tools::ListMyLibraries.call(user: @user, arguments: {})
    assert_equal [], result
  end

  test "manifest exposes name, description, and an empty input schema" do
    manifest = Mcp::Tools::ListMyLibraries.manifest
    assert_equal "list_my_libraries", manifest[:name]
    assert manifest[:description].present?
    assert_equal "object", manifest[:inputSchema][:type]
    assert_empty manifest[:inputSchema][:properties]
  end
end

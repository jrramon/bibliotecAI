# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_19_213722) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "books", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "added_by_user_id", null: false
    t.string "title", null: false
    t.string "author"
    t.string "isbn"
    t.string "goodreads_url"
    t.text "notes"
    t.string "slug", null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["added_by_user_id"], name: "index_books_on_added_by_user_id"
    t.index ["library_id", "slug"], name: "index_books_on_library_id_and_slug", unique: true
    t.index ["library_id"], name: "index_books_on_library_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "book_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["book_id"], name: "index_comments_on_book_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.string "scope"
    t.datetime "created_at"
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "invited_by_id", null: false
    t.string "email", null: false
    t.string "token", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_invitations_on_invited_by_id"
    t.index ["library_id", "email"], name: "index_invitations_on_library_id_and_email", unique: true, where: "(accepted_at IS NULL)"
    t.index ["library_id"], name: "index_invitations_on_library_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "libraries", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.bigint "owner_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_libraries_on_owner_id"
    t.index ["slug"], name: "index_libraries_on_slug", unique: true
  end

  create_table "memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "library_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id"], name: "index_memberships_on_library_id"
    t.index ["user_id", "library_id"], name: "index_memberships_on_user_id_and_library_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "shelf_photos", force: :cascade do |t|
    t.bigint "library_id", null: false
    t.bigint "uploaded_by_user_id", null: false
    t.integer "status", default: 0, null: false
    t.jsonb "claude_raw_response"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["library_id", "created_at"], name: "index_shelf_photos_on_library_id_and_created_at"
    t.index ["library_id"], name: "index_shelf_photos_on_library_id"
    t.index ["uploaded_by_user_id"], name: "index_shelf_photos_on_uploaded_by_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "books", "libraries"
  add_foreign_key "books", "users", column: "added_by_user_id"
  add_foreign_key "comments", "books"
  add_foreign_key "comments", "users"
  add_foreign_key "invitations", "libraries"
  add_foreign_key "invitations", "users", column: "invited_by_id"
  add_foreign_key "libraries", "users", column: "owner_id"
  add_foreign_key "memberships", "libraries"
  add_foreign_key "memberships", "users"
  add_foreign_key "shelf_photos", "libraries"
  add_foreign_key "shelf_photos", "users", column: "uploaded_by_user_id"
end

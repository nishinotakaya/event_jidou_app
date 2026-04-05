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

ActiveRecord::Schema[7.2].define(version: 2026_04_05_130101) do
  create_table "app_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "folders", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "folder_type"
    t.string "name"
    t.string "parent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_folders_on_user_id"
  end

  create_table "github_reviews", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "github_url", null: false
    t.string "github_type"
    t.string "repo_full_name"
    t.integer "pr_number"
    t.string "author"
    t.string "onclass_post_id"
    t.string "item_id"
    t.string "status", default: "pending"
    t.text "review_content"
    t.text "github_comment_url"
    t.text "images"
    t.integer "user_id"
    t.datetime "reviewed_at"
    t.datetime "posted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["github_url"], name: "index_github_reviews_on_github_url", unique: true
    t.index ["item_id"], name: "index_github_reviews_on_item_id"
    t.index ["status"], name: "index_github_reviews_on_status"
  end

  create_table "items", id: :string, charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "item_type"
    t.string "name"
    t.text "content"
    t.string "folder", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.string "event_date"
    t.string "event_time"
    t.string "event_end_time"
    t.text "onclass_mentions"
    t.text "onclass_channels"
    t.string "student_post_type"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "onclass_students", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "name"
    t.string "course"
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "posting_histories", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "item_id", null: false
    t.string "site_name", null: false
    t.string "status", default: "success", null: false
    t.string "event_url"
    t.boolean "published", default: false
    t.text "error_message"
    t.datetime "posted_at"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "registrations"
    t.datetime "registrations_checked_at"
    t.index ["item_id", "site_name"], name: "index_posting_histories_on_item_id_and_site_name"
    t.index ["item_id"], name: "index_posting_histories_on_item_id"
  end

  create_table "service_connections", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.bigint "user_id"
    t.string "service_name"
    t.string "email"
    t.string "encrypted_password_field"
    t.string "encrypted_password_field_iv"
    t.string "status"
    t.datetime "last_connected_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "session_data"
    t.index ["user_id", "service_name"], name: "index_service_connections_on_user_id_and_service_name", unique: true
    t.index ["user_id"], name: "index_service_connections_on_user_id"
  end

  create_table "users", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "name"
    t.string "provider"
    t.string "uid"
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "google_access_token"
    t.text "google_refresh_token"
    t.datetime "google_token_expires_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "zoom_settings", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "zoom_url"
    t.string "meeting_id"
    t.string "passcode"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
  end

  add_foreign_key "folders", "users"
  add_foreign_key "items", "users"
  add_foreign_key "service_connections", "users"
end

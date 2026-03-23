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

ActiveRecord::Schema[7.2].define(version: 2026_03_23_112510) do
  create_table "app_settings", force: :cascade do |t|
    t.string "key"
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "folders", force: :cascade do |t|
    t.string "folder_type"
    t.string "name"
    t.string "parent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "items", id: :string, force: :cascade do |t|
    t.string "item_type"
    t.string "name"
    t.text "content"
    t.string "folder", default: ""
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["user_id"], name: "index_items_on_user_id"
  end

  create_table "service_connections", force: :cascade do |t|
    t.integer "user_id"
    t.string "service_name"
    t.string "email"
    t.string "encrypted_password_field"
    t.string "encrypted_password_field_iv"
    t.string "status"
    t.datetime "last_connected_at"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "service_name"], name: "index_service_connections_on_user_id_and_service_name", unique: true
    t.index ["user_id"], name: "index_service_connections_on_user_id"
  end

  create_table "users", force: :cascade do |t|
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
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "zoom_settings", force: :cascade do |t|
    t.string "zoom_url"
    t.string "meeting_id"
    t.string "passcode"
    t.string "label"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "title"
  end

  add_foreign_key "items", "users"
  add_foreign_key "service_connections", "users"
end

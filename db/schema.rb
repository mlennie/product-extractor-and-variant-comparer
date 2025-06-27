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

ActiveRecord::Schema[8.0].define(version: 2025_06_27_182424) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "extraction_jobs", force: :cascade do |t|
    t.string "url", null: false
    t.string "status", default: "queued", null: false
    t.integer "progress", default: 0, null: false
    t.json "result_data"
    t.text "error_message"
    t.bigint "product_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_extraction_jobs_on_created_at"
    t.index ["product_id"], name: "index_extraction_jobs_on_product_id"
    t.index ["status"], name: "index_extraction_jobs_on_status"
  end

  create_table "product_variants", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.string "name", null: false
    t.string "quantity_text"
    t.decimal "quantity_numeric", precision: 10, scale: 2
    t.integer "price_cents", null: false
    t.integer "price_per_unit_cents"
    t.string "currency", default: "USD", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["currency"], name: "index_product_variants_on_currency"
    t.index ["price_per_unit_cents"], name: "index_product_variants_on_price_per_unit_cents"
    t.index ["product_id", "price_per_unit_cents"], name: "index_product_variants_on_product_id_and_price_per_unit_cents"
    t.index ["product_id"], name: "index_product_variants_on_product_id"
    t.check_constraint "price_cents >= 0", name: "non_negative_price"
    t.check_constraint "price_per_unit_cents >= 0", name: "non_negative_price_per_unit"
    t.check_constraint "quantity_numeric >= 0::numeric", name: "non_negative_quantity"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.text "url", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_products_on_created_at"
    t.index ["status"], name: "index_products_on_status"
    t.index ["url"], name: "index_products_on_url", unique: true
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying, 'processing'::character varying, 'completed'::character varying, 'failed'::character varying]::text[])", name: "valid_status"
  end

  add_foreign_key "extraction_jobs", "products"
  add_foreign_key "product_variants", "products"
end

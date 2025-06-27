class CreateProductVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :product_variants do |t|
      t.references :product, null: false, foreign_key: true
      t.string :name, null: false
      t.string :quantity_text
      t.decimal :quantity_numeric, precision: 10, scale: 2
      t.integer :price_cents, null: false
      t.integer :price_per_unit_cents
      t.string :currency, null: false, default: 'USD'

      t.timestamps
    end

    # Add indexes for efficient queries
    add_index :product_variants, :price_per_unit_cents
    add_index :product_variants, [:product_id, :price_per_unit_cents]
    add_index :product_variants, :currency
    
    # Add check constraints for data validation
    add_check_constraint :product_variants, "price_cents >= 0", name: 'non_negative_price'
    add_check_constraint :product_variants, "price_per_unit_cents >= 0", name: 'non_negative_price_per_unit'
    add_check_constraint :product_variants, "quantity_numeric >= 0", name: 'non_negative_quantity'
  end
end

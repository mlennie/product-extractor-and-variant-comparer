class CreateProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :products do |t|
      t.string :name, null: false
      t.text :url, null: false
      t.string :status, null: false, default: 'pending'

      t.timestamps
    end

    # Add indexes for efficient queries
    add_index :products, :status
    add_index :products, :url, unique: true
    add_index :products, :created_at
    
    # Add check constraint for valid status values
    add_check_constraint :products, "status IN ('pending', 'processing', 'completed', 'failed')", name: 'valid_status'
  end
end

class CreateExtractionJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :extraction_jobs do |t|
      t.string :url, null: false
      t.string :status, default: 'queued', null: false
      t.integer :progress, default: 0, null: false
      t.json :result_data
      t.text :error_message
      t.references :product, null: true, foreign_key: true

      t.timestamps
    end
    
    add_index :extraction_jobs, :status
    add_index :extraction_jobs, :created_at
  end
end

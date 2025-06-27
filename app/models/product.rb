class Product < ApplicationRecord
  # Associations
  has_many :product_variants, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :url, presence: true, uniqueness: true, format: { 
    with: /\Ahttps?:\/\/.+\z/, 
    message: 'must be a valid HTTP or HTTPS URL' 
  }
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }

  # Scopes
  scope :by_status, ->(status) { where(status: status) }
  scope :completed, -> { where(status: 'completed') }
  scope :processing, -> { where(status: 'processing') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }

  # Status transition methods
  def mark_as_processing!
    update!(status: 'processing')
  end

  def mark_as_completed!
    update!(status: 'completed')
  end

  def mark_as_failed!
    update!(status: 'failed')
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def pending?
    status == 'pending'
  end

  # Business logic methods
  def best_value_variant
    product_variants.where.not(price_per_unit_cents: nil)
                   .order(:price_per_unit_cents)
                   .first
  end

  def has_variants?
    product_variants.any?
  end

  def variant_count
    product_variants.count
  end

  def average_price_per_unit
    return 0 if product_variants.empty?
    
    variants_with_price = product_variants.where.not(price_per_unit_cents: nil)
    return 0 if variants_with_price.empty?
    
    (variants_with_price.average(:price_per_unit_cents) || 0).to_f
  end
end

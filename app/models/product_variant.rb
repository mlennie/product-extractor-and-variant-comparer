class ProductVariant < ApplicationRecord
  belongs_to :product

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :price_cents, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :currency, presence: true, length: { is: 3 }
  validates :quantity_numeric, numericality: { greater_than: 0 }, allow_nil: true
  validates :price_per_unit_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Callbacks
  before_save :calculate_price_per_unit

  # Scopes
  scope :with_price_per_unit, -> { where.not(price_per_unit_cents: nil) }
  scope :by_best_value, -> { with_price_per_unit.order(:price_per_unit_cents) }
  scope :by_price, -> { order(:price_cents) }
  scope :by_quantity, -> { order(:quantity_numeric) }

  # Price methods
  def price
    price_cents / 100.0
  end

  def price_per_unit
    return nil unless price_per_unit_cents
    price_per_unit_cents / 100.0
  end

  def formatted_price
    format_currency(price_cents)
  end

  def formatted_price_per_unit
    return 'N/A' unless price_per_unit_cents
    format_currency(price_per_unit_cents)
  end

  # Quantity methods
  def has_quantity?
    quantity_numeric.present? && quantity_numeric > 0
  end

  def quantity_display
    return quantity_text if quantity_text.present?
    return quantity_numeric.to_i.to_s if quantity_numeric.present?
    'N/A'
  end

  # Comparison methods
  def is_best_value?
    return false unless price_per_unit_cents
    
    product.product_variants.with_price_per_unit.minimum(:price_per_unit_cents) == price_per_unit_cents
  end

  def value_rank
    return nil unless price_per_unit_cents
    
    better_variants = product.product_variants.with_price_per_unit
                            .where('price_per_unit_cents < ?', price_per_unit_cents)
                            .count
    better_variants + 1
  end

  private

  def calculate_price_per_unit
    if quantity_numeric.present? && quantity_numeric > 0 && price_cents.present?
      self.price_per_unit_cents = (price_cents.to_f / quantity_numeric).round
    else
      self.price_per_unit_cents = nil
    end
  end

  def format_currency(cents)
    return '$0.00' if cents.nil? || cents == 0
    
    # Convert cents to dollars and format with currency symbol
    dollars = cents / 100.0
    currency_symbol = case currency.upcase
                     when 'USD' then '$'
                     when 'EUR' then '€'
                     when 'GBP' then '£'
                     else currency
                     end
    
    "#{currency_symbol}#{'%.2f' % dollars}"
  end
end

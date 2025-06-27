require 'rails_helper'

RSpec.describe ProductVariant, type: :model do
  # Factory validation
  it "has a valid factory" do
    expect(build(:product_variant)).to be_valid
  end

  # Validations
  describe "validations" do
    subject { build(:product_variant) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:price_cents) }
    it { should validate_presence_of(:currency) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:currency).is_equal_to(3) }
    it { should validate_numericality_of(:price_cents).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:quantity_numeric).is_greater_than(0).allow_nil }
    it { should validate_numericality_of(:price_per_unit_cents).is_greater_than_or_equal_to(0).allow_nil }
  end

  # Associations
  describe "associations" do
    it { should belong_to(:product) }
  end

  # Callbacks
  describe "callbacks" do
    describe "calculate_price_per_unit callback" do
      it "calculates price per unit when quantity and price are present" do
        variant = build(:product_variant, quantity_numeric: 50, price_cents: 1000)
        variant.save!
        expect(variant.price_per_unit_cents).to eq(20) # 1000 / 50 = 20 cents per unit
      end

      it "sets price_per_unit_cents to nil when quantity is missing" do
        variant = build(:product_variant, quantity_numeric: nil, price_cents: 1000)
        variant.save!
        expect(variant.price_per_unit_cents).to be_nil
      end

      it "sets price_per_unit_cents to nil when quantity is zero" do
        variant = build(:product_variant, quantity_numeric: 0, price_cents: 1000)
        variant.save!(validate: false) # Skip validation for this test case
        expect(variant.price_per_unit_cents).to be_nil
      end

      it "rounds fractional cents correctly" do
        variant = build(:product_variant, quantity_numeric: 3, price_cents: 100)
        variant.save!
        expect(variant.price_per_unit_cents).to eq(33) # 100 / 3 = 33.33... rounded to 33
      end
    end
  end

  # Scopes
  describe "scopes" do
    let(:product) { create(:product) }
    let!(:variant_with_price_per_unit) { create(:product_variant, product: product, quantity_numeric: 10, price_cents: 1000) }
    let!(:variant_without_price_per_unit) { create(:product_variant, :without_quantity, product: product) }

    describe ".with_price_per_unit" do
      it "returns only variants with price_per_unit_cents" do
        results = ProductVariant.with_price_per_unit
        expect(results).to include(variant_with_price_per_unit)
        expect(results).not_to include(variant_without_price_per_unit)
      end
    end

    describe ".by_best_value" do
      let!(:expensive_variant) { create(:product_variant, product: product, quantity_numeric: 10, price_cents: 2000) }
      let!(:cheap_variant) { create(:product_variant, product: product, quantity_numeric: 10, price_cents: 500) }

      it "orders variants by price_per_unit_cents ascending" do
        results = ProductVariant.by_best_value
        expect(results.first).to eq(cheap_variant)
        expect(results.last).to eq(expensive_variant)
      end
    end

    describe ".by_price" do
      it "orders variants by price_cents ascending" do
        # Clear any existing variants to ensure clean test
        ProductVariant.where(product: product).delete_all
        
        expensive_variant = create(:product_variant, 
          product: product, 
          name: "Expensive Variant",
          price_cents: 2000, 
          quantity_numeric: 10
        )
        cheap_variant = create(:product_variant, 
          product: product, 
          name: "Cheap Variant",
          price_cents: 500, 
          quantity_numeric: 10
        )

        results = ProductVariant.where(product: product).by_price
        expect(results.first).to eq(cheap_variant)
        expect(results.last).to eq(expensive_variant)
      end
    end

    describe ".by_quantity" do
      it "orders variants by quantity_numeric ascending" do
        # Clear any existing variants to ensure clean test
        ProductVariant.where(product: product).delete_all
        
        large_variant = create(:product_variant, 
          product: product, 
          name: "Large Variant",
          quantity_numeric: 100, 
          price_cents: 1000
        )
        small_variant = create(:product_variant, 
          product: product, 
          name: "Small Variant",
          quantity_numeric: 10, 
          price_cents: 1000
        )

        results = ProductVariant.where(product: product).by_quantity
        expect(results.first).to eq(small_variant)
        expect(results.last).to eq(large_variant)
      end
    end
  end

  # Price methods
  describe "price methods" do
    let(:variant) { create(:product_variant, price_cents: 1500, currency: "USD") }

    describe "#price" do
      it "returns price in dollars" do
        expect(variant.price).to eq(15.0)
      end
    end

    describe "#price_per_unit" do
      it "returns price per unit in dollars when available" do
        # Use update_column to bypass callbacks that recalculate price_per_unit_cents
        variant.update_column(:price_per_unit_cents, 150)
        expect(variant.price_per_unit).to eq(1.5)
      end

      it "returns nil when price_per_unit_cents is nil" do
        variant.update!(price_per_unit_cents: nil, quantity_numeric: nil)
        expect(variant.reload.price_per_unit).to be_nil
      end
    end

    describe "#formatted_price" do
      it "formats USD prices correctly" do
        expect(variant.formatted_price).to eq("$15.00")
      end

      it "formats EUR prices correctly" do
        variant.update!(currency: "EUR")
        expect(variant.formatted_price).to eq("€15.00")
      end

      it "formats GBP prices correctly" do
        variant.update!(currency: "GBP")
        expect(variant.formatted_price).to eq("£15.00")
      end

      it "handles unknown currencies" do
        variant.update!(currency: "XYZ")
        expect(variant.formatted_price).to eq("XYZ15.00")
      end
    end

    describe "#formatted_price_per_unit" do
      it "formats price per unit when available" do
        # Use update_column to bypass callbacks that recalculate price_per_unit_cents
        variant.update_column(:price_per_unit_cents, 150)
        expect(variant.formatted_price_per_unit).to eq("$1.50")
      end

      it "returns 'N/A' when price_per_unit_cents is nil" do
        variant.update!(price_per_unit_cents: nil, quantity_numeric: nil)
        expect(variant.reload.formatted_price_per_unit).to eq("N/A")
      end
    end
  end

  # Quantity methods
  describe "quantity methods" do
    describe "#has_quantity?" do
      it "returns true when quantity_numeric is present and positive" do
        variant = build(:product_variant, quantity_numeric: 10)
        expect(variant.has_quantity?).to be true
      end

      it "returns false when quantity_numeric is nil" do
        variant = build(:product_variant, quantity_numeric: nil)
        expect(variant.has_quantity?).to be false
      end

      it "returns false when quantity_numeric is zero" do
        variant = build(:product_variant, quantity_numeric: 0)
        expect(variant.has_quantity?).to be false
      end

      it "returns false when quantity_numeric is negative" do
        variant = build(:product_variant, quantity_numeric: -5)
        expect(variant.has_quantity?).to be false
      end
    end

    describe "#quantity_display" do
      it "returns quantity_text when present" do
        variant = build(:product_variant, quantity_text: "30 tablets", quantity_numeric: 30)
        expect(variant.quantity_display).to eq("30 tablets")
      end

      it "returns quantity_numeric as string when quantity_text is blank" do
        variant = build(:product_variant, quantity_text: "", quantity_numeric: 30)
        expect(variant.quantity_display).to eq("30")
      end

      it "returns 'N/A' when both quantity fields are blank" do
        variant = build(:product_variant, quantity_text: nil, quantity_numeric: nil)
        expect(variant.quantity_display).to eq("N/A")
      end
    end
  end

  # Comparison methods
  describe "comparison methods" do
    let(:product) { create(:product) }

    describe "#is_best_value?" do
      it "returns true for the variant with lowest price per unit" do
        best_variant = create(:product_variant, product: product, quantity_numeric: 100, price_cents: 1000) # $0.10 per unit
        worse_variant = create(:product_variant, product: product, quantity_numeric: 50, price_cents: 1000)  # $0.20 per unit

        expect(best_variant.is_best_value?).to be true
        expect(worse_variant.is_best_value?).to be false
      end

      it "returns false when price_per_unit_cents is nil" do
        variant = create(:product_variant, :without_quantity, product: product)
        expect(variant.is_best_value?).to be false
      end

      it "handles ties correctly (both return true)" do
        variant1 = create(:product_variant, product: product, quantity_numeric: 10, price_cents: 1000)
        variant2 = create(:product_variant, product: product, quantity_numeric: 10, price_cents: 1000)

        expect(variant1.is_best_value?).to be true
        expect(variant2.is_best_value?).to be true
      end
    end

    describe "#value_rank" do
      it "returns correct ranking based on price per unit" do
        best_variant = create(:product_variant, product: product, quantity_numeric: 100, price_cents: 1000)   # $0.10 per unit - rank 1
        middle_variant = create(:product_variant, product: product, quantity_numeric: 50, price_cents: 1000)  # $0.20 per unit - rank 2
        worst_variant = create(:product_variant, product: product, quantity_numeric: 25, price_cents: 1000)   # $0.40 per unit - rank 3

        expect(best_variant.value_rank).to eq(1)
        expect(middle_variant.value_rank).to eq(2)
        expect(worst_variant.value_rank).to eq(3)
      end

      it "returns nil when price_per_unit_cents is nil" do
        variant = create(:product_variant, :without_quantity, product: product)
        expect(variant.value_rank).to be_nil
      end
    end
  end

  # Integration with Product
  describe "integration with Product" do
    it "is destroyed when product is destroyed" do
      product = create(:product)
      variant = create(:product_variant, product: product)
      
      expect { product.destroy }.to change { ProductVariant.count }.by(-1)
    end

    it "updates product's best_value_variant calculation" do
      product = create(:product)
      best_variant = create(:product_variant, product: product, quantity_numeric: 100, price_cents: 1000)
      worse_variant = create(:product_variant, product: product, quantity_numeric: 50, price_cents: 1000)

      expect(product.best_value_variant).to eq(best_variant)
    end
  end
end

require 'rails_helper'

RSpec.describe Product, type: :model do
  # Factory validation
  it "has a valid factory" do
    expect(build(:product)).to be_valid
  end

  # Validations
  describe "validations" do
    subject { build(:product) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:url) }
    it { should validate_presence_of(:status) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_uniqueness_of(:url) }
    it { should validate_inclusion_of(:status).in_array(%w[pending processing completed failed]) }

    describe "URL format validation" do
      it "accepts valid URLs" do
        valid_urls = [
          "https://example.com",
          "http://test.com/product/123",
          "https://shop.example.com/products/abc-def?id=123"
        ]
        
        valid_urls.each do |url|
          product = build(:product, url: url)
          expect(product).to be_valid, "Expected #{url} to be valid"
        end
      end

      it "rejects invalid URLs" do
        invalid_urls = [
          "not-a-url",
          "ftp://invalid",
          "just-text",
          ""
        ]
        
        invalid_urls.each do |url|
          product = build(:product, url: url)
          expect(product).not_to be_valid, "Expected #{url} to be invalid"
        end
      end
    end
  end

  # Associations
  describe "associations" do
    it { should have_many(:product_variants).dependent(:destroy) }
  end

  # Scopes
  describe "scopes" do
    let!(:pending_product) { create(:product, :pending) }
    let!(:processing_product) { create(:product, :processing) }
    let!(:completed_product) { create(:product, :completed) }
    let!(:failed_product) { create(:product, :failed) }

    describe ".by_status" do
      it "returns products with the specified status" do
        expect(Product.by_status('pending')).to include(pending_product)
        expect(Product.by_status('pending')).not_to include(processing_product)
      end
    end

    describe ".pending" do
      it "returns only pending products" do
        expect(Product.pending).to include(pending_product)
        expect(Product.pending).not_to include(completed_product)
      end
    end

    describe ".processing" do
      it "returns only processing products" do
        expect(Product.processing).to include(processing_product)
        expect(Product.processing).not_to include(pending_product)
      end
    end

    describe ".completed" do
      it "returns only completed products" do
        expect(Product.completed).to include(completed_product)
        expect(Product.completed).not_to include(failed_product)
      end
    end

    describe ".failed" do
      it "returns only failed products" do
        expect(Product.failed).to include(failed_product)
        expect(Product.failed).not_to include(completed_product)
      end
    end

    describe ".recent" do
      it "orders products by created_at desc" do
        # Clear any existing products to avoid interference
        Product.delete_all
        
        older_product = Product.create!(
          name: "Older Product",
          url: "https://example.com/older",
          status: "pending",
          created_at: 2.days.ago
        )
        newer_product = Product.create!(
          name: "Newer Product", 
          url: "https://example.com/newer",
          status: "pending",
          created_at: 1.day.ago
        )
        
        recent_products = Product.recent
        expect(recent_products.first).to eq(newer_product)
        expect(recent_products.second).to eq(older_product)
      end
    end
  end

  # Status transition methods
  describe "status transition methods" do
    let(:product) { create(:product, :pending) }

    describe "#mark_as_processing!" do
      it "changes status to processing" do
        expect { product.mark_as_processing! }.to change { product.status }.to("processing")
      end

      it "persists the change" do
        product.mark_as_processing!
        expect(product.reload.status).to eq("processing")
      end
    end

    describe "#mark_as_completed!" do
      it "changes status to completed" do
        expect { product.mark_as_completed! }.to change { product.status }.to("completed")
      end
    end

    describe "#mark_as_failed!" do
      it "changes status to failed" do
        expect { product.mark_as_failed! }.to change { product.status }.to("failed")
      end
    end
  end

  # Status query methods
  describe "status query methods" do
    it "returns correct status for pending product" do
      product = create(:product, :pending)
      expect(product.pending?).to be true
      expect(product.processing?).to be false
      expect(product.completed?).to be false
      expect(product.failed?).to be false
    end

    it "returns correct status for completed product" do
      product = create(:product, :completed)
      expect(product.pending?).to be false
      expect(product.processing?).to be false
      expect(product.completed?).to be true
      expect(product.failed?).to be false
    end
  end

  # Business logic methods
  describe "business logic methods" do
    describe "#best_value_variant" do
      let(:product) { create(:product, :with_best_value_variant) }

      it "returns the variant with the lowest price per unit" do
        best_variant = product.best_value_variant
        expect(best_variant.price_per_unit_cents).to eq(20) # $0.20 per unit (2000 cents / 100)
      end

      it "returns nil when no variants exist" do
        empty_product = create(:product)
        expect(empty_product.best_value_variant).to be_nil
      end

      it "returns nil when no variants have price_per_unit_cents" do
        product = create(:product)
        create(:product_variant, product: product, price_per_unit_cents: nil, quantity_numeric: nil)
        expect(product.best_value_variant).to be_nil
      end
    end

    describe "#has_variants?" do
      it "returns true when product has variants" do
        product = create(:product, :with_variants)
        expect(product.has_variants?).to be true
      end

      it "returns false when product has no variants" do
        product = create(:product)
        expect(product.has_variants?).to be false
      end
    end

    describe "#variant_count" do
      it "returns the correct count of variants" do
        product = create(:product)
        create_list(:product_variant, 3, product: product)
        expect(product.variant_count).to eq(3)
      end
    end

    describe "#average_price_per_unit" do
      it "calculates the average price per unit correctly" do
        product = create(:product)
        # Create variants with specific, predictable values
        variant1 = create(:product_variant, product: product, quantity_numeric: 10, price_cents: 1000) # 100 cents per unit
        variant2 = create(:product_variant, product: product, quantity_numeric: 10, price_cents: 2000) # 200 cents per unit
        
        # Average should be (100 + 200) / 2 = 150.0
        expect(product.average_price_per_unit).to eq(150.0)
      end

      it "returns 0 when no variants exist" do
        product = create(:product)
        expect(product.average_price_per_unit).to eq(0)
      end

      it "returns 0 when no variants have price_per_unit_cents" do
        product = create(:product)
        create(:product_variant, product: product, price_per_unit_cents: nil, quantity_numeric: nil)
        expect(product.average_price_per_unit).to eq(0)
      end
    end
  end
end

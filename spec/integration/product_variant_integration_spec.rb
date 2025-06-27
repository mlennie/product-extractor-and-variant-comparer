require 'rails_helper'

RSpec.describe "Product and ProductVariant Integration", type: :model do
  describe "price per unit calculations and best value logic" do
    let(:product) { create(:product) }

    context "when product has multiple variants with different value propositions" do
      before do
        # Create variants with different price per unit values
        @bulk_variant = create(:product_variant, 
          product: product, 
          name: "Bulk Pack",
          quantity_numeric: 100, 
          price_cents: 2500,  # $25.00 for 100 = $0.25 per unit
          quantity_text: "100 tablets"
        )
        
        @medium_variant = create(:product_variant,
          product: product,
          name: "Medium Pack", 
          quantity_numeric: 50,
          price_cents: 1500,  # $15.00 for 50 = $0.30 per unit
          quantity_text: "50 tablets"
        )
        
        @small_variant = create(:product_variant,
          product: product,
          name: "Small Pack",
          quantity_numeric: 20,
          price_cents: 800,   # $8.00 for 20 = $0.40 per unit
          quantity_text: "20 tablets"
        )
      end

      it "correctly calculates price per unit for all variants" do
        expect(@bulk_variant.price_per_unit_cents).to eq(25)   # $0.25 per unit
        expect(@medium_variant.price_per_unit_cents).to eq(30) # $0.30 per unit  
        expect(@small_variant.price_per_unit_cents).to eq(40)  # $0.40 per unit
      end

      it "identifies the best value variant correctly" do
        best_value = product.best_value_variant
        expect(best_value).to eq(@bulk_variant)
        expect(best_value.is_best_value?).to be true
      end

      it "ranks variants correctly by value" do
        expect(@bulk_variant.value_rank).to eq(1)   # Best value
        expect(@medium_variant.value_rank).to eq(2) # Second best
        expect(@small_variant.value_rank).to eq(3)  # Worst value
      end

      it "calculates average price per unit correctly" do
        # (25 + 30 + 40) / 3 = 31.67 cents per unit
        expect(product.average_price_per_unit.round(2)).to eq(31.67)
      end

      describe "when best value variant is removed" do
        it "updates the best value to the next best option" do
          expect(product.best_value_variant).to eq(@bulk_variant)
          
          @bulk_variant.destroy
          
          expect(product.reload.best_value_variant).to eq(@medium_variant)
          expect(@medium_variant.is_best_value?).to be true
        end
      end
    end

    context "when variants have same price per unit" do
      before do
        @variant1 = create(:product_variant,
          product: product,
          quantity_numeric: 50,
          price_cents: 1000  # $10.00 for 50 = $0.20 per unit
        )
        
        @variant2 = create(:product_variant,
          product: product, 
          quantity_numeric: 100,
          price_cents: 2000  # $20.00 for 100 = $0.20 per unit
        )
      end

      it "both variants are considered best value" do
        expect(@variant1.is_best_value?).to be true
        expect(@variant2.is_best_value?).to be true
      end

      it "both variants have rank 1" do
        expect(@variant1.value_rank).to eq(1)
        expect(@variant2.value_rank).to eq(1)
      end

      it "returns the first created variant as best_value_variant" do
        # ActiveRecord's .first returns the first record by primary key
        best_value = product.best_value_variant
        expect(best_value).to eq(@variant1)
      end
    end

    context "when variants lack quantity information" do
      before do
        @variant_with_quantity = create(:product_variant,
          product: product,
          quantity_numeric: 30,
          quantity_text: nil,
          price_cents: 900
        )
        
        @variant_without_quantity = create(:product_variant,
          product: product,
          quantity_numeric: nil,
          quantity_text: "Family size",
          price_cents: 1200
        )
      end

      it "only includes variants with quantity in best value calculations" do
        expect(product.best_value_variant).to eq(@variant_with_quantity)
        expect(@variant_without_quantity.is_best_value?).to be false
      end

      it "excludes variants without quantity from average calculations" do
        expect(product.average_price_per_unit).to eq(30.0) # Only counts the variant with quantity
      end

      it "handles quantity display appropriately" do
        expect(@variant_with_quantity.quantity_display).to eq("30")
        expect(@variant_without_quantity.quantity_display).to eq("Family size")
      end
    end

    context "currency formatting and display" do
      before do
        @usd_variant = create(:product_variant,
          product: product,
          price_cents: 1599,
          currency: "USD"
        )
        
        @eur_variant = create(:product_variant,
          product: product,
          price_cents: 1299,
          currency: "EUR"
        )
      end

      it "formats different currencies correctly" do
        expect(@usd_variant.formatted_price).to eq("$15.99")
        expect(@eur_variant.formatted_price).to eq("€12.99")
      end

      it "handles edge cases in pricing" do
        zero_price_variant = create(:product_variant, product: product, price_cents: 0)
        expect(zero_price_variant.formatted_price).to eq("$0.00")
      end
    end
  end

  describe "product status and variant lifecycle" do
    let(:product) { create(:product, :pending) }

    it "allows variants to be added to products in any status" do
      expect { create(:product_variant, product: product) }.to change { product.variant_count }.by(1)
      
      product.mark_as_processing!
      expect { create(:product_variant, product: product) }.to change { product.variant_count }.by(1)
      
      product.mark_as_completed!
      expect { create(:product_variant, product: product) }.to change { product.variant_count }.by(1)
    end

    it "destroys all variants when product is destroyed" do
      create_list(:product_variant, 3, product: product)
      
      expect { product.destroy }.to change { ProductVariant.count }.by(-3)
    end

    context "when replacing product variants (re-extraction scenario)" do
      before do
        @old_variants = create_list(:product_variant, 2, product: product)
      end

      it "can replace all variants with new data" do
        # Simulate replacing variants (as would happen during re-extraction)
        old_count = product.variant_count
        
        # Remove old variants
        product.product_variants.destroy_all
        
        # Add new variants
        new_variants = create_list(:product_variant, 3, product: product)
        
        expect(product.reload.variant_count).to eq(3)
        expect(product.product_variants).to match_array(new_variants)
      end
    end
  end

  describe "database constraints and validations integration" do
    let(:product) { create(:product) }

    it "enforces non-negative price constraints at database level" do
      expect {
        # Bypass model validations to test database constraint directly
        variant = ProductVariant.new(
          product: product,
          name: "Invalid Variant",
          price_cents: -100,
          currency: "USD"
        )
        variant.save!(validate: false)
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "enforces proper currency length" do
      variant = build(:product_variant, product: product, currency: "INVALID")
      expect(variant).not_to be_valid
      expect(variant.errors[:currency]).to be_present
    end

    it "enforces unique product URLs" do
      existing_product = create(:product, url: "https://example.com/product")
      duplicate_product = build(:product, url: "https://example.com/product")
      
      expect(duplicate_product).not_to be_valid
      expect(duplicate_product.errors[:url]).to be_present
    end
  end
end 
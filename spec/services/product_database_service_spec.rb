require 'rails_helper'

RSpec.describe ProductDatabaseService do
  let(:service) { described_class.new }

  describe '#save_product_data' do
    let(:sample_url) { 'https://example.com/product' }
    let(:valid_extracted_data) do
      {
        'product' => {
          'name' => 'Coca-Cola Classic',
          'description' => 'Classic Coca-Cola soft drink'
        },
        'variants' => [
          {
            'name' => '12 oz Can',
            'quantity_text' => '12 oz',
            'quantity_numeric' => 12.0,
            'price_cents' => 129,
            'currency' => 'USD'
          },
          {
            'name' => '20 oz Bottle',
            'quantity_text' => '20 oz',
            'quantity_numeric' => 20.0,
            'price_cents' => 199,
            'currency' => 'USD'
          }
        ]
      }
    end

    context 'with valid data' do
      it 'creates a new product and variants successfully' do
        result = service.save_product_data(valid_extracted_data, sample_url)

        expect(result[:success]).to be true
        expect(result[:errors]).to be_empty
        expect(result[:product]).to be_a(Product)
        expect(result[:variants]).to be_an(Array)
        expect(result[:variants].size).to eq(2)
        expect(result[:best_value_variant]).to be_a(ProductVariant)
        expect(result[:processing_time]).to be > 0
      end

      it 'creates product with correct attributes' do
        result = service.save_product_data(valid_extracted_data, sample_url)
        product = result[:product]

        expect(product.name).to eq('Coca-Cola Classic')
        expect(product.url).to eq(sample_url)
        expect(product.status).to eq('completed')
      end

      it 'creates variants with correct attributes' do
        result = service.save_product_data(valid_extracted_data, sample_url)
        variants = result[:variants]

        expect(variants[0].name).to eq('12 oz Can')
        expect(variants[0].quantity_text).to eq('12 oz')
        expect(variants[0].quantity_numeric).to eq(12.0)
        expect(variants[0].price_cents).to eq(129)
        expect(variants[0].currency).to eq('USD')
        expect(variants[0].price_per_unit_cents).to eq(11) # 129/12 rounded

        expect(variants[1].name).to eq('20 oz Bottle')
        expect(variants[1].quantity_numeric).to eq(20.0)
        expect(variants[1].price_cents).to eq(199)
        expect(variants[1].price_per_unit_cents).to eq(10) # 199/20 rounded
      end

      it 'identifies the best value variant' do
        result = service.save_product_data(valid_extracted_data, sample_url)
        best_variant = result[:best_value_variant]

        expect(best_variant.name).to eq('20 oz Bottle')
        expect(best_variant.price_per_unit_cents).to eq(10)
      end

      it 'updates existing product without creating duplicates' do
        # Create first time
        first_result = service.save_product_data(valid_extracted_data, sample_url)
        first_product_id = first_result[:product].id

        # Update with new data
        updated_data = valid_extracted_data.deep_dup
        updated_data['variants'] = [
          {
            'name' => '16 oz Bottle',
            'quantity_text' => '16 oz',
            'quantity_numeric' => 16.0,
            'price_cents' => 149,
            'currency' => 'USD'
          }
        ]

        second_result = service.save_product_data(updated_data, sample_url)

        expect(second_result[:success]).to be true
        expect(second_result[:product].id).to eq(first_product_id)
        expect(second_result[:variants].size).to eq(1)
        expect(second_result[:variants][0].name).to eq('16 oz Bottle')

        # Verify old variants were removed
        expect(Product.find(first_product_id).product_variants.count).to eq(1)
      end
    end

    context 'with invalid data' do
      it 'returns error for nil data' do
        result = service.save_product_data(nil, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('No extracted data provided')
      end

      it 'returns error for blank URL' do
        result = service.save_product_data(valid_extracted_data, '')

        expect(result[:success]).to be false
        expect(result[:errors]).to include('URL is required')
      end

      it 'returns error for missing product section' do
        invalid_data = { 'variants' => [{ 'name' => 'Test', 'price_cents' => 100 }] }
        result = service.save_product_data(invalid_data, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Invalid data structure: Missing product section')
      end

      it 'returns error for missing variants section' do
        invalid_data = { 'product' => { 'name' => 'Test' } }
        result = service.save_product_data(invalid_data, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Invalid data structure: Missing variants section')
      end

      it 'returns error for empty variants array' do
        invalid_data = { 
          'product' => { 'name' => 'Test' },
          'variants' => []
        }
        result = service.save_product_data(invalid_data, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Invalid data structure: At least one variant is required')
      end

      it 'returns error for variant with missing name' do
        invalid_data = valid_extracted_data.deep_dup
        invalid_data['variants'][0].delete('name')
        
        result = service.save_product_data(invalid_data, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Invalid data structure: Variant 1: Name is required')
      end

      it 'returns error for variant with invalid price_cents' do
        invalid_data = valid_extracted_data.deep_dup
        invalid_data['variants'][0]['price_cents'] = -10
        
        result = service.save_product_data(invalid_data, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Invalid data structure: Variant 1: price_cents must be a non-negative integer')
      end
    end

    context 'database transaction handling' do
      it 'rolls back transaction on database error' do
        allow_any_instance_of(ProductVariant).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(ProductVariant.new))

        expect {
          service.save_product_data(valid_extracted_data, sample_url)
        }.not_to change(Product, :count)

        result = service.save_product_data(valid_extracted_data, sample_url)
        expect(result[:success]).to be false
        expect(result[:errors]).to include(match(/Database validation error/))
      end
    end
  end

  describe '#mark_product_as_processing' do
    let(:sample_url) { 'https://example.com/product' }

    it 'creates new product with processing status' do
      result = service.mark_product_as_processing(sample_url)

      expect(result[:success]).to be true
      expect(result[:product]).to be_a(Product)
      expect(result[:product].status).to eq('processing')
      expect(result[:product].url).to eq(sample_url)
      expect(result[:errors]).to be_empty
    end

    it 'updates existing product to processing status' do
      existing_product = create(:product, url: sample_url, status: 'pending')

      result = service.mark_product_as_processing(sample_url)

      expect(result[:success]).to be true
      expect(result[:product].id).to eq(existing_product.id)
      expect(result[:product].status).to eq('processing')
    end

    it 'extracts domain name for new products' do
      result = service.mark_product_as_processing('https://www.amazon.com/product/123')

      expect(result[:product].name).to eq('amazon.com')
    end
  end

  describe '#mark_product_as_failed' do
    let(:sample_url) { 'https://example.com/product' }
    let(:error_message) { 'Test error message' }

    it 'creates new product with failed status' do
      result = service.mark_product_as_failed(sample_url, error_message)

      expect(result[:success]).to be true
      expect(result[:product]).to be_a(Product)
      expect(result[:product].status).to eq('failed')
      expect(result[:error_message]).to eq(error_message)
    end

    it 'updates existing product to failed status' do
      existing_product = create(:product, url: sample_url, status: 'processing')

      result = service.mark_product_as_failed(sample_url, error_message)

      expect(result[:success]).to be true
      expect(result[:product].id).to eq(existing_product.id)
      expect(result[:product].status).to eq('failed')
    end
  end

  describe 'private methods' do
    describe '#extract_domain_from_url' do
      it 'extracts domain from various URL formats' do
        service_instance = service.send(:class).new

        expect(service_instance.send(:extract_domain_from_url, 'https://www.amazon.com/product')).to eq('amazon.com')
        expect(service_instance.send(:extract_domain_from_url, 'https://example.com')).to eq('example.com')
        expect(service_instance.send(:extract_domain_from_url, 'http://subdomain.example.com/path')).to eq('subdomain.example.com')
        expect(service_instance.send(:extract_domain_from_url, 'invalid-url')).to eq('Unknown Product')
      end
    end
  end
end 
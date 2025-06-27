require 'rails_helper'

RSpec.describe 'AI Product Extraction Step 3 Integration', type: :integration do
  let(:sample_url) { 'https://example.com/test-product' }
  let(:sample_html) do
    <<~HTML
      <html>
        <head><title>Coca-Cola Classic - Multiple Sizes</title></head>
        <body>
          <h1>Coca-Cola Classic</h1>
          <p>The original Coca-Cola taste</p>
          
          <div class="product-variants">
            <div class="variant">
              <h3>12 oz Can</h3>
              <p>Price: $1.29</p>
              <p>Quantity: 12 fl oz</p>
            </div>
            
            <div class="variant">
              <h3>20 oz Bottle</h3>
              <p>Price: $1.99</p>
              <p>Quantity: 20 fl oz</p>
            </div>
            
            <div class="variant">
              <h3>2 Liter Bottle</h3>
              <p>Price: $2.49</p>
              <p>Quantity: 2 liters (67.6 fl oz)</p>
            </div>
          </div>
        </body>
      </html>
    HTML
  end

  let(:expected_ai_response) do
    {
      "product" => {
        "name" => "Coca-Cola Classic",
        "description" => "The original Coca-Cola taste"
      },
      "variants" => [
        {
          "name" => "12 oz Can",
          "quantity_text" => "12 fl oz",
          "quantity_numeric" => 12.0,
          "price_cents" => 129,
          "currency" => "USD"
        },
        {
          "name" => "20 oz Bottle",
          "quantity_text" => "20 fl oz",
          "quantity_numeric" => 20.0,
          "price_cents" => 199,
          "currency" => "USD"
        },
        {
          "name" => "2 Liter Bottle",
          "quantity_text" => "2 liters",
          "quantity_numeric" => 67.6,
          "price_cents" => 249,
          "currency" => "USD"
        }
      ]
    }
  end

  before do
    # Clean up any existing test data
    Product.where(url: sample_url).destroy_all
    
    # Mock the web fetcher to return our sample HTML
    allow_any_instance_of(WebPageFetcher).to receive(:fetch).with(sample_url).and_return({
      success: true,
      content: sample_html,
      status_code: 200,
      response_time: 1.2,
      errors: []
    })

    # Mock the OpenAI API to return our expected structured response
    mock_openai_response = {
      "choices" => [
        {
          "message" => {
            "content" => expected_ai_response.to_json
          }
        }
      ]
    }
    
    allow_any_instance_of(OpenAI::Client).to receive(:chat).and_return(mock_openai_response)
    
    # Ensure API key is available
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-api-key')
  end

  describe 'Complete Pipeline: URL -> HTML -> AI -> Database' do
    it 'successfully extracts and saves product data' do
      extractor = ProductDataExtractor.new
      
      result = extractor.extract_from_url(sample_url)

      # Verify successful completion
      expect(result[:success]).to be true
      expect(result[:processing_time]).to be > 0
      expect(result[:errors]).to be_empty

      # Verify product was created
      expect(result[:product]).to be_a(Product)
      expect(result[:product].name).to eq('Coca-Cola Classic')
      expect(result[:product].url).to eq(sample_url)
      expect(result[:product].status).to eq('completed')

      # Verify variants were created
      expect(result[:variants]).to be_an(Array)
      expect(result[:variants].size).to eq(3)

      # Check first variant
      variant_12oz = result[:variants].find { |v| v.name == '12 oz Can' }
      expect(variant_12oz).to be_present
      expect(variant_12oz.quantity_text).to eq('12 fl oz')
      expect(variant_12oz.quantity_numeric).to eq(12.0)
      expect(variant_12oz.price_cents).to eq(129)
      expect(variant_12oz.currency).to eq('USD')
      expect(variant_12oz.price_per_unit_cents).to eq(11) # 129/12 rounded

      # Check second variant
      variant_20oz = result[:variants].find { |v| v.name == '20 oz Bottle' }
      expect(variant_20oz).to be_present
      expect(variant_20oz.quantity_numeric).to eq(20.0)
      expect(variant_20oz.price_cents).to eq(199)
      expect(variant_20oz.price_per_unit_cents).to eq(10) # 199/20 rounded

      # Check third variant
      variant_2l = result[:variants].find { |v| v.name == '2 Liter Bottle' }
      expect(variant_2l).to be_present
      expect(variant_2l.quantity_numeric).to eq(67.6)
      expect(variant_2l.price_cents).to eq(249)
      expect(variant_2l.price_per_unit_cents).to eq(4) # 249/67.6 rounded

      # Verify best value variant identification
      expect(result[:best_value_variant]).to be_a(ProductVariant)
      expect(result[:best_value_variant].name).to eq('2 Liter Bottle')
      expect(result[:best_value_variant].price_per_unit_cents).to eq(4)

      # Verify database persistence
      saved_product = Product.find_by(url: sample_url)
      expect(saved_product).to be_present
      expect(saved_product.product_variants.count).to eq(3)
      expect(saved_product.best_value_variant.name).to eq('2 Liter Bottle')
    end

    it 'includes comprehensive processing details' do
      extractor = ProductDataExtractor.new
      
      result = extractor.extract_from_url(sample_url)

      expect(result[:details]).to be_a(Hash)
      
      # Fetch result details
      expect(result[:details][:fetch_result]).to include(
        :status_code,
        :content_length,
        :response_time
      )
      expect(result[:details][:fetch_result][:status_code]).to eq(200)
      expect(result[:details][:fetch_result][:content_length]).to eq(sample_html.length)

      # Extraction result details
      expect(result[:details][:extraction_result]).to include(
        :model_used,
        :response_time,
        :raw_response_length
      )
      expect(result[:details][:extraction_result][:model_used]).to eq('gpt-3.5-turbo')

      # Database result details
      expect(result[:details][:database_result]).to include(
        :variants_created,
        :processing_time
      )
      expect(result[:details][:database_result][:variants_created]).to eq(3)
    end

    it 'calculates price-per-unit correctly for all variants' do
      extractor = ProductDataExtractor.new
      
      result = extractor.extract_from_url(sample_url)

      variants = result[:variants].sort_by(&:price_per_unit_cents)
      
      # Best value (lowest price per unit)
      expect(variants[0].name).to eq('2 Liter Bottle')
      expect(variants[0].price_per_unit_cents).to eq(4) # $0.04 per fl oz
      
      # Middle value
      expect(variants[1].name).to eq('20 oz Bottle')
      expect(variants[1].price_per_unit_cents).to eq(10) # $0.10 per fl oz
      
      # Highest price per unit
      expect(variants[2].name).to eq('12 oz Can')
      expect(variants[2].price_per_unit_cents).to eq(11) # $0.11 per fl oz
    end

    it 'handles duplicate URLs by updating existing products' do
      # First extraction
      extractor = ProductDataExtractor.new
      first_result = extractor.extract_from_url(sample_url)
      first_product_id = first_result[:product].id
      
      # Second extraction with same URL
      second_result = extractor.extract_from_url(sample_url)
      
      # Should reuse same product record
      expect(second_result[:product].id).to eq(first_product_id)
      expect(Product.where(url: sample_url).count).to eq(1)
      
      # Should have updated variants (old ones replaced)
      expect(second_result[:variants].count).to eq(3)
      expect(ProductVariant.where(product_id: first_product_id).count).to eq(3)
    end
  end

  describe 'Error Handling in Full Pipeline' do
    context 'when web fetching fails' do
      before do
        allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
          success: false,
          errors: ['HTTP 404: Not Found']
        })
      end

      it 'marks product as failed and returns error' do
        extractor = ProductDataExtractor.new
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:product]).to be_nil
        expect(result[:variants]).to be_empty
        expect(result[:errors]).to include('HTTP 404: Not Found')
        
        # Product should be marked as failed in database
        failed_product = Product.find_by(url: sample_url)
        expect(failed_product).to be_present
        expect(failed_product.status).to eq('failed')
      end
    end

    context 'when AI extraction fails' do
      before do
        allow_any_instance_of(OpenAI::Client).to receive(:chat).and_raise(
          OpenAI::Error.new('Rate limit exceeded')
        )
      end

      it 'marks product as failed and returns error' do
        extractor = ProductDataExtractor.new
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include(match(/Rate limit exceeded/))
        
        # Product should be marked as failed
        failed_product = Product.find_by(url: sample_url)
        expect(failed_product.status).to eq('failed')
      end
    end

    context 'when AI returns invalid JSON' do
      before do
        allow_any_instance_of(OpenAI::Client).to receive(:chat).and_return({
          "choices" => [
            {
              "message" => {
                "content" => "This is not valid JSON response"
              }
            }
          ]
        })
      end

      it 'marks product as failed for invalid structured data' do
        extractor = ProductDataExtractor.new
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include(match(/Invalid JSON response|No structured data extracted/))
        
        failed_product = Product.find_by(url: sample_url)
        expect(failed_product.status).to eq('failed')
      end
    end

    context 'when database validation fails' do
      before do
        # Mock a database validation error
        allow_any_instance_of(ProductVariant).to receive(:save!).and_raise(
          ActiveRecord::RecordInvalid.new(ProductVariant.new)
        )
      end

      it 'rolls back transaction and marks product as failed' do
        extractor = ProductDataExtractor.new
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include(match(/Database validation error/))
        
        # Should not have created any variants due to rollback
        product = Product.find_by(url: sample_url)
        expect(product.status).to eq('failed')
        expect(product.product_variants.count).to eq(0)
      end
    end
  end

  describe 'Extract Without Saving' do
    it 'extracts data but does not save to database' do
      extractor = ProductDataExtractor.new
      
      # Ensure no product exists initially
      expect(Product.where(url: sample_url).count).to eq(0)
      
      result = extractor.extract_without_saving(sample_url)

      expect(result[:success]).to be true
      expect(result[:stage]).to eq('extraction_completed')
      expect(result[:extracted_data]).to be_a(Hash)
      expect(result[:extracted_data]['product']['name']).to eq('Coca-Cola Classic')
      expect(result[:extracted_data]['variants'].size).to eq(3)
      
      # Should not have saved anything to database
      expect(Product.where(url: sample_url).count).to eq(0)
      expect(ProductVariant.count).to eq(0)
    end
  end

  describe 'System Health and Pipeline Tests' do
    it 'reports healthy system status' do
      extractor = ProductDataExtractor.new
      
      health = extractor.health_check

      expect(health[:web_fetcher][:available]).to be true
      expect(health[:ai_extractor][:available]).to be true
      expect(health[:ai_extractor][:api_key_configured]).to be true
      expect(health[:database_service][:available]).to be true
      expect(health[:database_service][:database_connected]).to be true
      expect(health[:overall_status]).to eq('ready')
    end

    it 'successfully tests complete pipeline' do
      allow_any_instance_of(WebPageFetcher).to receive(:fetch).with('https://httpbin.org/html').and_return({
        success: true,
        status_code: 200,
        response_time: 1.0
      })
      
      allow_any_instance_of(AiContentExtractor).to receive(:test_connection).and_return({
        success: true,
        response: 'Connection successful'
      })

      extractor = ProductDataExtractor.new
      
      result = extractor.test_pipeline

      expect(result[:success]).to be true
      expect(result[:stage]).to eq('completed')
      expect(result[:message]).to eq('Full pipeline test successful')
      expect(result[:details]).to include(:web_fetch_status, :ai_connection_response, :database_service)
    end
  end
end 
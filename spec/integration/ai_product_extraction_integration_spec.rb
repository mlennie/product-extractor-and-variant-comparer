require 'rails_helper'

RSpec.describe 'AI Product Extraction Integration', type: :integration do
  let(:extractor) { ProductDataExtractor.new }
  
  describe 'Complete extraction pipeline' do
    context 'with realistic product HTML' do
      let(:product_html) do
        <<~HTML
          <html>
          <head><title>Nike Air Max 90 - Athletic Shoes</title></head>
          <body>
            <h1>Nike Air Max 90 Athletic Shoes</h1>
            <div class="product-info">
              <div class="variants">
                <div class="variant" data-size="8" data-price="120.00">
                  <span class="size">Size 8</span>
                  <span class="price">$120.00</span>
                </div>
                <div class="variant" data-size="9" data-price="120.00">
                  <span class="size">Size 9</span>
                  <span class="price">$120.00</span>
                </div>
                <div class="variant" data-size="10" data-price="125.00">
                  <span class="size">Size 10</span>
                  <span class="price">$125.00</span>
                </div>
              </div>
              <div class="description">
                <p>Classic athletic shoe with Air Max cushioning technology.</p>
                <p>Available in multiple sizes with premium materials.</p>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      before do
        # Mock the web fetcher to return our test HTML
        allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
          success: true,
          content: product_html,
          url: 'https://example-store.com/nike-air-max',
          status_code: 200,
          response_time: 1.2,
          errors: []
        })
      end

      it 'successfully extracts product information using real AI', :vcr do
        # Skip this test if no API key is configured
        skip "OpenAI API key not configured" unless ENV['OPENAI_API_KEY'].present?

        result = extractor.extract_from_url('https://example-store.com/nike-air-max')

        expect(result[:success]).to be true
        expect(result[:product]).to be_a(Product)
        expect(result[:product].name).to include('Nike')
        expect(result[:variants]).to be_an(Array)
        expect(result[:processing_time]).to be > 0
        expect(result[:errors]).to be_empty
      end

      it 'handles the complete flow from URL to extracted data', :vcr do
        # Skip this test if no API key is configured
        skip "OpenAI API key not configured" unless ENV['OPENAI_API_KEY'].present?

        start_time = Time.current
        result = extractor.extract_from_url('https://example-store.com/nike-air-max')
        end_time = Time.current

        # Verify timing is reasonable (should be under 10 seconds for this test)
        expect(end_time - start_time).to be < 10

        # Verify structure (Step 3 format)
        expect(result).to have_key(:success)
        expect(result).to have_key(:product)
        expect(result).to have_key(:variants)
        expect(result).to have_key(:best_value_variant)
        expect(result).to have_key(:details)

        # Verify details contain fetch, extraction, and database results
        expect(result[:details]).to have_key(:fetch_result)
        expect(result[:details]).to have_key(:extraction_result)
        expect(result[:details]).to have_key(:database_result)
        expect(result[:details][:fetch_result][:content_length]).to eq(product_html.length)
      end
    end

    context 'error scenarios' do
      it 'handles web fetch failures gracefully' do
        # Mock a web fetch failure
        allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
          success: false,
          content: nil,
          url: 'https://invalid-url.com',
          status_code: nil,
          response_time: 30.0,
          errors: ['Request timed out']
        })

        result = extractor.extract_from_url('https://invalid-url.com')

        expect(result[:success]).to be false
        expect(result[:product]).to be_nil
        expect(result[:variants]).to be_empty
        expect(result[:errors]).to include('Request timed out')
      end

      it 'handles AI extraction failures gracefully' do
        # Mock successful web fetch but AI failure
        allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
          success: true,
          content: '<html><body>Test</body></html>',
          url: 'https://example.com',
          status_code: 200,
          response_time: 1.0,
          errors: []
        })

        # Mock AI failure
        allow_any_instance_of(AiContentExtractor).to receive(:extract_product_data).and_return({
          success: false,
          data: nil,
          url: 'https://example.com',
          model_used: 'gpt-3.5-turbo',
          errors: ['OpenAI API error: Rate limit exceeded']
        })

        result = extractor.extract_from_url('https://example.com')

        expect(result[:success]).to be false
        expect(result[:product]).to be_nil
        expect(result[:variants]).to be_empty
        expect(result[:errors]).to include('OpenAI API error: Rate limit exceeded')
      end
    end

    context 'system health and monitoring' do
      it 'provides accurate health check information' do
        health = extractor.health_check

        expect(health).to have_key(:web_fetcher)
        expect(health).to have_key(:ai_extractor)
        expect(health).to have_key(:overall_status)

        expect(health[:web_fetcher][:available]).to be true
        expect(health[:web_fetcher][:class]).to eq('WebPageFetcher')
        expect(health[:ai_extractor][:class]).to eq('AiContentExtractor')
      end

      it 'accurately reports API key status' do
        health = extractor.health_check

        if ENV['OPENAI_API_KEY'].present?
          expect(health[:ai_extractor][:available]).to be true
          expect(health[:ai_extractor][:api_key_configured]).to be true
          expect(health[:overall_status]).to eq('ready')
        else
          expect(health[:ai_extractor][:available]).to be false
          expect(health[:ai_extractor][:api_key_configured]).to be false
          expect(health[:overall_status]).to eq('missing_api_key')
        end
      end
    end
  end

  describe 'Performance characteristics' do
    let(:simple_html) do
      <<~HTML
        <html>
          <body>
            <h1>Test Product</h1>
            <div class="product-info">
              <div class="variant">
                <span class="variant-name">Standard Size</span>
                <span class="price">$19.99</span>
                <span class="quantity">1 unit</span>
              </div>
            </div>
          </body>
        </html>
      HTML
    end

    before do
      allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
        success: true,
        content: simple_html,
        url: 'https://example.com',
        status_code: 200,
        response_time: 0.5,
        errors: []
      })
    end

    it 'completes extraction in reasonable time', :vcr do
      skip "OpenAI API key not configured" unless ENV['OPENAI_API_KEY'].present?

      start_time = Time.current
      result = extractor.extract_from_url('https://example.com')
      end_time = Time.current

      total_time = end_time - start_time

      expect(result[:success]).to be true
      expect(result[:product]).to be_a(Product)
      expect(result[:variants]).to be_an(Array)
      # Should complete within 10 seconds for simple content
      expect(total_time).to be < 10
      expect(result[:processing_time]).to be_between(0.1, total_time + 0.1)
    end

    it 'measures processing time accurately' do
      # Mock AI to return valid structured data
      allow_any_instance_of(AiContentExtractor).to receive(:extract_product_data) do
        sleep(0.1) # Simulate processing time
        {
          success: true,
          data: {
            'product' => { 'name' => 'Test Product' },
            'variants' => [{ 'name' => 'Test Variant', 'price_cents' => 1999, 'currency' => 'USD' }]
          },
          url: 'https://example.com',
          model_used: 'gpt-3.5-turbo',
          response_time: 0.1,
          errors: []
        }
      end

      result = extractor.extract_from_url('https://example.com')

      expect(result[:success]).to be true
      expect(result[:product]).to be_a(Product)
      expect(result[:processing_time]).to be >= 0.1
      expect(result[:processing_time]).to be < 1.0
    end
  end
end 
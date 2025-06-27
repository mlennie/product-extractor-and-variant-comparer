require 'rails_helper'

RSpec.describe ProductDataExtractor, type: :service do
  let(:extractor) { described_class.new }
  let(:sample_url) { 'https://example.com/product' }
  let(:sample_html) { '<html><body><h1>Test Product</h1><p>Price: $19.99</p></body></html>' }
  
  let(:mock_web_fetcher) { double('WebPageFetcher') }
  let(:mock_ai_extractor) { double('AiContentExtractor') }
  let(:mock_database_service) { double('ProductDatabaseService') }

  let(:successful_fetch_result) do
    {
      success: true,
      content: sample_html,
      status_code: 200,
      response_time: 1.2,
      errors: []
    }
  end

  let(:successful_extraction_result) do
    {
      success: true,
      data: {
        'product' => {
          'name' => 'Test Product',
          'description' => 'Product description'
        },
        'variants' => [
          {
            'name' => '12 oz Can',
            'quantity_text' => '12 oz',
            'quantity_numeric' => 12.0,
            'price_cents' => 199,
            'currency' => 'USD'
          }
        ]
      },
      raw_response: '{"product": {"name": "Test Product"}}',
      url: sample_url,
      model_used: 'gpt-3.5-turbo',
      response_time: 2.1,
      errors: []
    }
  end

  let(:successful_database_result) do
    {
      success: true,
      product: create(:product, name: 'Test Product', url: sample_url, status: 'completed'),
      variants: [create(:product_variant, name: '12 oz Can', price_cents: 199)],
      best_value_variant: create(:product_variant, name: '12 oz Can', price_cents: 199),
      processing_time: 0.5,
      errors: []
    }
  end

  before do
    allow(WebPageFetcher).to receive(:new).and_return(mock_web_fetcher)
    allow(AiContentExtractor).to receive(:new).and_return(mock_ai_extractor)
    allow(ProductDatabaseService).to receive(:new).and_return(mock_database_service)
  end

  describe '#extract_from_url' do
    context 'successful full pipeline' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: true, product: double('Product'), errors: [] })
        allow(mock_web_fetcher).to receive(:fetch) do
          sleep(0.01)
          successful_fetch_result
        end
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return(successful_extraction_result)
        allow(mock_database_service).to receive(:save_product_data).and_return(successful_database_result)
      end

      it 'completes the full pipeline and returns database records' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be true
        expect(result[:product]).to be_a(Product)
        expect(result[:variants]).to be_an(Array)
        expect(result[:best_value_variant]).to be_a(ProductVariant)
        expect(result[:processing_time]).to be > 0
        expect(result[:errors]).to be_empty
      end

      it 'includes detailed processing information' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:details]).to include(:fetch_result, :extraction_result, :database_result)
        expect(result[:details][:fetch_result]).to include(:status_code, :content_length, :response_time)
        expect(result[:details][:extraction_result]).to include(:model_used, :response_time, :raw_response_length)
        expect(result[:details][:database_result]).to include(:variants_created, :processing_time)
      end

      it 'marks product as processing at start' do
        expect(mock_database_service).to receive(:mark_product_as_processing).with(sample_url)
        extractor.extract_from_url(sample_url)
      end

      it 'calls services in correct order' do
        expect(mock_database_service).to receive(:mark_product_as_processing).ordered
        expect(mock_web_fetcher).to receive(:fetch).ordered
        expect(mock_ai_extractor).to receive(:extract_product_data).ordered
        expect(mock_database_service).to receive(:save_product_data).ordered

        extractor.extract_from_url(sample_url)
      end
    end

    context 'database setup failure' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: false, errors: ['Database error'] })
      end

      it 'returns error for database setup failure' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:product]).to be_nil
        expect(result[:variants]).to be_empty
        expect(result[:best_value_variant]).to be_nil
        expect(result[:errors]).to include('Database error')
      end
    end

    context 'web fetching failure' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: true, product: double('Product'), errors: [] })
        allow(mock_web_fetcher).to receive(:fetch).and_return({ success: false, errors: ['Failed to fetch'] })
        allow(mock_database_service).to receive(:mark_product_as_failed)
      end

      it 'marks product as failed and returns error' do
        expect(mock_database_service).to receive(:mark_product_as_failed).with(sample_url, match(/Failed to fetch webpage/))
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:product]).to be_nil
        expect(result[:errors]).to include('Failed to fetch')
      end
    end

    context 'AI extraction failure' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: true, product: double('Product'), errors: [] })
        allow(mock_web_fetcher).to receive(:fetch).and_return(successful_fetch_result)
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return({ success: false, errors: ['AI extraction failed'] })
        allow(mock_database_service).to receive(:mark_product_as_failed)
      end

      it 'marks product as failed and returns error' do
        expect(mock_database_service).to receive(:mark_product_as_failed).with(sample_url, match(/Failed to extract data/))
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('AI extraction failed')
      end
    end

    context 'data validation failure' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: true, product: double('Product'), errors: [] })
        allow(mock_web_fetcher).to receive(:fetch).and_return(successful_fetch_result)
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return({ success: true, data: nil, errors: [] })
        allow(mock_database_service).to receive(:mark_product_as_failed)
      end

      it 'marks product as failed for missing data' do
        expect(mock_database_service).to receive(:mark_product_as_failed).with(sample_url, match(/No structured data extracted/))
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('No structured data extracted from AI response')
      end
    end

    context 'database save failure' do
      before do
        allow(mock_database_service).to receive(:mark_product_as_processing).and_return({ success: true, product: double('Product'), errors: [] })
        allow(mock_web_fetcher).to receive(:fetch).and_return(successful_fetch_result)
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return(successful_extraction_result)
        allow(mock_database_service).to receive(:save_product_data).and_return({ success: false, errors: ['Database save failed'] })
        allow(mock_database_service).to receive(:mark_product_as_failed)
      end

      it 'marks product as failed and returns error' do
        expect(mock_database_service).to receive(:mark_product_as_failed).with(sample_url, match(/Failed to save data/))
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Database save failed')
      end
    end
  end

  describe '#extract_without_saving' do
    context 'successful extraction without database save' do
      before do
        allow(mock_web_fetcher).to receive(:fetch) do
          sleep(0.01)
          successful_fetch_result
        end
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return(successful_extraction_result)
      end

      it 'returns extracted data without saving to database' do
        result = extractor.extract_without_saving(sample_url)

        expect(result[:success]).to be true
        expect(result[:url]).to eq(sample_url)
        expect(result[:stage]).to eq('extraction_completed')
        expect(result[:extracted_data]).to be_a(Hash)
        expect(result[:extracted_data]['product']['name']).to eq('Test Product')
        expect(result[:processing_time]).to be > 0
      end

      it 'does not call database service' do
        expect(mock_database_service).not_to receive(:mark_product_as_processing)
        expect(mock_database_service).not_to receive(:save_product_data)
        
        extractor.extract_without_saving(sample_url)
      end
    end

    context 'fetch failure' do
      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return({ success: false, errors: ['Fetch failed'] })
      end

      it 'returns error without database interaction' do
        result = extractor.extract_without_saving(sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include('Fetch failed')
      end
    end
  end

  describe '#test_pipeline' do
    let(:mock_web_test_result) { { success: true, status_code: 200, response_time: 1.0 } }
    let(:mock_ai_test_result) { { success: true, response: 'Connection successful' } }
    let(:mock_database_test_result) { { success: true, message: 'Database operational' } }

    before do
      allow(mock_web_fetcher).to receive(:fetch).and_return(mock_web_test_result)
      allow(mock_ai_extractor).to receive(:test_connection).and_return(mock_ai_test_result)
      allow(extractor).to receive(:test_database_service).and_return(mock_database_test_result)
    end

    it 'tests all pipeline components' do
      result = extractor.test_pipeline

      expect(result[:success]).to be true
      expect(result[:stage]).to eq('completed')
      expect(result[:message]).to eq('Full pipeline test successful')
      expect(result[:details]).to include(:web_fetch_status, :ai_connection_response, :database_service)
    end

    context 'when database test fails' do
      before do
        allow(extractor).to receive(:test_database_service).and_return({ success: false, errors: ['DB error'] })
      end

      it 'returns database test failure' do
        result = extractor.test_pipeline

        expect(result[:success]).to be false
        expect(result[:stage]).to eq('database_test')
        expect(result[:errors]).to include('Database service test failed: DB error')
      end
    end
  end

  describe '#health_check' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
      allow(extractor).to receive(:database_connected?).and_return(true)
    end

    it 'returns comprehensive health status' do
      result = extractor.health_check

      expect(result[:web_fetcher]).to include(:available, :class)
      expect(result[:ai_extractor]).to include(:available, :api_key_configured, :class)
      expect(result[:database_service]).to include(:available, :class, :database_connected)
      expect(result[:overall_status]).to eq('ready')
    end

    context 'when API key is missing' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
      end

      it 'returns missing_api_key status' do
        result = extractor.health_check
        expect(result[:overall_status]).to eq('missing_api_key')
      end
    end

    context 'when database is not connected' do
      before do
        allow(extractor).to receive(:database_connected?).and_return(false)
      end

      it 'returns database_error status' do
        result = extractor.health_check
        expect(result[:overall_status]).to eq('database_error')
      end
    end
  end

  describe 'private methods' do
    describe '#test_database_service' do
      it 'tests database connectivity' do
        allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
        allow(Product).to receive(:count).and_return(5)
        
        result = extractor.send(:test_database_service)
        
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Database service operational (5 products)')
      end

      it 'reconnects if connection is not active' do
        allow(ActiveRecord::Base.connection).to receive(:active?).and_return(false)
        allow(ActiveRecord::Base.connection).to receive(:reconnect!)
        allow(Product).to receive(:count).and_return(3)
        
        result = extractor.send(:test_database_service)
        
        expect(ActiveRecord::Base.connection).to have_received(:reconnect!)
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Database service operational (3 products)')
      end

      it 'handles database errors' do
        allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)
        allow(Product).to receive(:count).and_raise(StandardError.new('DB error'))
        
        result = extractor.send(:test_database_service)
        
        expect(result[:success]).to be false
        expect(result[:errors]).to include('DB error')
      end
    end

    describe '#database_connected?' do
      it 'returns true when database is connected' do
        allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1").and_return(true)
        
        expect(extractor.send(:database_connected?)).to be true
      end

      it 'returns false when database connection fails' do
        allow(ActiveRecord::Base.connection).to receive(:execute).with("SELECT 1").and_raise(StandardError)
        
        expect(extractor.send(:database_connected?)).to be false
      end
    end
  end
end 
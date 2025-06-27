require 'rails_helper'

RSpec.describe ProductDataExtractor, type: :service do
  let(:extractor) { ProductDataExtractor.new }
  let(:sample_url) { 'https://example.com/product' }
  let(:sample_html) { '<html><body><h1>Test Product</h1><p>Price: $19.99</p></body></html>' }

  # Mock the internal services
  let(:mock_web_fetcher) { double('WebPageFetcher') }
  let(:mock_ai_extractor) { double('AiContentExtractor') }

  before do
    allow(WebPageFetcher).to receive(:new).and_return(mock_web_fetcher)
    allow(AiContentExtractor).to receive(:new).and_return(mock_ai_extractor)
  end

  describe '#extract_from_url' do
    context 'successful extraction' do
      let(:successful_fetch_result) do
        {
          success: true,
          content: sample_html,
          url: sample_url,
          status_code: 200,
          response_time: 1.2,
          errors: []
        }
      end

      let(:successful_ai_result) do
        {
          success: true,
          data: "Product: Test Product, Price: $19.99",
          url: sample_url,
          model_used: "gpt-3.5-turbo",
          errors: []
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(successful_fetch_result)
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return(successful_ai_result)
      end

      it 'successfully extracts product data from URL' do
        # Add a small delay to ensure measurable time
        allow(mock_web_fetcher).to receive(:fetch) do
          sleep(0.01)
          successful_fetch_result
        end
        
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be true
        expect(result[:url]).to eq(sample_url)
        expect(result[:stage]).to eq('completed')
        expect(result[:data]).to eq("Product: Test Product, Price: $19.99")
        expect(result[:processing_time]).to be > 0
        expect(result[:errors]).to be_empty
      end

      it 'includes detailed information in response' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:details][:fetch_result]).to eq(successful_fetch_result)
        expect(result[:details][:extraction_result]).to eq(successful_ai_result)
        expect(result[:details][:content_length]).to eq(sample_html.length)
        expect(result[:details][:model_used]).to eq("gpt-3.5-turbo")
      end

      it 'measures processing time accurately' do
        # Add a small delay to ensure measurable time
        allow(mock_web_fetcher).to receive(:fetch) do
          sleep(0.01)
          successful_fetch_result
        end
        
        start_time = Time.current
        result = extractor.extract_from_url(sample_url)
        end_time = Time.current

        expect(result[:processing_time]).to be_between(0.01, (end_time - start_time) + 0.1)
      end

      it 'calls web fetcher with correct URL' do
        expect(mock_web_fetcher).to receive(:fetch).with(sample_url).and_return(successful_fetch_result)
        
        extractor.extract_from_url(sample_url)
      end

      it 'calls AI extractor with fetched content' do
        expect(mock_ai_extractor).to receive(:extract_product_data)
          .with(sample_html, sample_url)
          .and_return(successful_ai_result)
        
        extractor.extract_from_url(sample_url)
      end
    end

    context 'web fetching fails' do
      let(:failed_fetch_result) do
        {
          success: false,
          content: nil,
          url: sample_url,
          status_code: 404,
          response_time: 1.0,
          errors: ['HTTP 404: Not Found']
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(failed_fetch_result)
      end

      it 'returns failure at fetch stage' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:stage]).to eq('fetch')
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include('HTTP 404: Not Found')
      end

      it 'includes fetch result in details' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:details][:fetch_result]).to eq(failed_fetch_result)
        expect(result[:details]).not_to have_key(:extraction_result)
      end

      it 'does not call AI extractor when fetch fails' do
        expect(mock_ai_extractor).not_to receive(:extract_product_data)
        
        extractor.extract_from_url(sample_url)
      end
    end

    context 'AI extraction fails' do
      let(:successful_fetch_result) do
        {
          success: true,
          content: sample_html,
          url: sample_url,
          status_code: 200,
          response_time: 1.2,
          errors: []
        }
      end

      let(:failed_ai_result) do
        {
          success: false,
          data: nil,
          url: sample_url,
          model_used: "gpt-3.5-turbo",
          errors: ['OpenAI API error: Rate limit exceeded']
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(successful_fetch_result)
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return(failed_ai_result)
      end

      it 'returns failure at extraction stage' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:success]).to be false
        expect(result[:stage]).to eq('extraction')
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include('OpenAI API error: Rate limit exceeded')
      end

      it 'includes both fetch and extraction results in details' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:details][:fetch_result]).to eq(successful_fetch_result)
        expect(result[:details][:extraction_result]).to eq(failed_ai_result)
      end
    end

    context 'response structure' do
      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return({
          success: true, content: sample_html, url: sample_url, 
          status_code: 200, response_time: 1.0, errors: []
        })
        allow(mock_ai_extractor).to receive(:extract_product_data).and_return({
          success: true, data: "test", url: sample_url, 
          model_used: "gpt-3.5-turbo", errors: []
        })
      end

      it 'always returns expected keys' do
        result = extractor.extract_from_url(sample_url)

        expect(result).to have_key(:success)
        expect(result).to have_key(:url)
        expect(result).to have_key(:stage)
        expect(result).to have_key(:data)
        expect(result).to have_key(:processing_time)
        expect(result).to have_key(:errors)
        expect(result).to have_key(:details)
      end

      it 'returns errors as an array' do
        result = extractor.extract_from_url(sample_url)

        expect(result[:errors]).to be_an(Array)
      end
    end
  end

  describe '#test_pipeline' do
    context 'when both services work' do
      let(:web_test_result) do
        {
          success: true,
          status_code: 200,
          response_time: 1.0,
          errors: []
        }
      end

      let(:ai_test_result) do
        {
          success: true,
          response: "Connection successful",
          errors: []
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(web_test_result)
        allow(mock_ai_extractor).to receive(:test_connection).and_return(ai_test_result)
      end

      it 'returns successful pipeline test' do
        # Add a small delay to ensure measurable time
        allow(mock_web_fetcher).to receive(:fetch) do
          sleep(0.01)
          web_test_result
        end
        
        result = extractor.test_pipeline

        expect(result[:success]).to be true
        expect(result[:stage]).to eq('completed')
        expect(result[:message]).to eq("Pipeline test successful")
        expect(result[:processing_time]).to be > 0
        expect(result[:errors]).to be_empty
      end

      it 'includes test details' do
        result = extractor.test_pipeline

        expect(result[:details][:web_fetch_status]).to eq(200)
        expect(result[:details][:web_fetch_time]).to eq(1.0)
        expect(result[:details][:ai_connection_response]).to eq("Connection successful")
      end
    end

    context 'when web fetcher fails' do
      let(:failed_web_result) do
        {
          success: false,
          errors: ['Connection timeout']
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(failed_web_result)
      end

      it 'returns failure at web fetch test stage' do
        result = extractor.test_pipeline

        expect(result[:success]).to be false
        expect(result[:stage]).to eq('web_fetch_test')
        expect(result[:errors]).to include('Web fetcher test failed: Connection timeout')
      end

      it 'does not test AI when web test fails' do
        expect(mock_ai_extractor).not_to receive(:test_connection)
        
        extractor.test_pipeline
      end
    end

    context 'when AI extractor fails' do
      let(:web_test_result) do
        {
          success: true,
          status_code: 200,
          response_time: 1.0,
          errors: []
        }
      end

      let(:failed_ai_result) do
        {
          success: false,
          errors: ['OpenAI API key not configured']
        }
      end

      before do
        allow(mock_web_fetcher).to receive(:fetch).and_return(web_test_result)
        allow(mock_ai_extractor).to receive(:test_connection).and_return(failed_ai_result)
      end

      it 'returns failure at AI connection test stage' do
        result = extractor.test_pipeline

        expect(result[:success]).to be false
        expect(result[:stage]).to eq('ai_connection_test')
        expect(result[:errors]).to include('AI extractor test failed: OpenAI API key not configured')
      end
    end
  end

  describe '#health_check' do
    context 'when API key is configured' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
        # Don't mock the classes for health check tests
        allow(WebPageFetcher).to receive(:new).and_call_original
        allow(AiContentExtractor).to receive(:new).and_call_original
      end

      it 'returns ready status' do
        real_extractor = ProductDataExtractor.new
        result = real_extractor.health_check

        expect(result[:web_fetcher][:available]).to be true
        expect(result[:web_fetcher][:class]).to eq('WebPageFetcher')
        expect(result[:ai_extractor][:available]).to be true
        expect(result[:ai_extractor][:api_key_configured]).to be true
        expect(result[:ai_extractor][:class]).to eq('AiContentExtractor')
        expect(result[:overall_status]).to eq('ready')
      end
    end

    context 'when API key is not configured' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
        # Don't mock the classes for health check tests
        allow(WebPageFetcher).to receive(:new).and_call_original
        allow(AiContentExtractor).to receive(:new).and_call_original
      end

      it 'returns missing API key status' do
        real_extractor = ProductDataExtractor.new
        result = real_extractor.health_check

        expect(result[:ai_extractor][:available]).to be false
        expect(result[:ai_extractor][:api_key_configured]).to be false
        expect(result[:overall_status]).to eq('missing_api_key')
      end
    end
  end

  describe 'initialization' do
    it 'creates WebPageFetcher instance' do
      expect(WebPageFetcher).to receive(:new)
      
      ProductDataExtractor.new
    end

    it 'creates AiContentExtractor instance' do
      expect(AiContentExtractor).to receive(:new)
      
      ProductDataExtractor.new
    end
  end
end 
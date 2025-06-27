require 'rails_helper'

RSpec.describe AiContentExtractor, type: :service do
  let(:extractor) { AiContentExtractor.new }
  let(:sample_html) { '<html><body><h1>Test Product</h1><p>Price: $19.99</p></body></html>' }
  let(:sample_url) { 'https://example.com/product' }

  # Mock OpenAI client
  let(:mock_client) { double('OpenAI::Client') }
  let(:successful_json_response) do
    {
      "product" => {
        "name" => "Test Product",
        "description" => "Sample product description"
      },
      "variants" => [
        {
          "name" => "Standard Size",
          "quantity_text" => "1 unit",
          "quantity_numeric" => 1.0,
          "price_cents" => 1999,
          "currency" => "USD"
        }
      ]
    }
  end
  let(:successful_response) do
    {
      "choices" => [
        {
          "message" => {
            "content" => successful_json_response.to_json
          }
        }
      ]
    }
  end

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
  end

  describe '#test_connection' do
    context 'when API key is not configured' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return(nil)
      end

      it 'returns error for missing API key' do
        result = extractor.test_connection

        expect(result[:success]).to be false
        expect(result[:errors]).to include("OpenAI API key not configured")
      end
    end

    context 'when API key is configured' do
      before do
        allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
      end

      it 'successfully tests connection' do
        allow(mock_client).to receive(:chat).and_return({
          "choices" => [
            {
              "message" => {
                "content" => "Connection successful"
              }
            }
          ]
        })

        result = extractor.test_connection

        expect(result[:success]).to be true
        expect(result[:response]).to eq("Connection successful")
        expect(result[:errors]).to be_empty
      end

      it 'handles OpenAI authentication errors' do
        allow(mock_client).to receive(:chat).and_raise(OpenAI::Error.new("Invalid API key"))

        result = extractor.test_connection

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Authentication failed: Invalid API key")
      end

      it 'handles OpenAI rate limit errors' do
        allow(mock_client).to receive(:chat).and_raise(OpenAI::Error.new("Rate limit exceeded"))

        result = extractor.test_connection

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Rate limit exceeded: Please try again later")
      end

      it 'handles timeout errors' do
        allow(mock_client).to receive(:chat).and_raise(Faraday::TimeoutError.new("Request timeout"))

        result = extractor.test_connection

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Request timeout: OpenAI API took too long to respond")
      end

      it 'handles connection failures' do
        allow(mock_client).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("Connection failed"))

        result = extractor.test_connection

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Connection failed: Unable to connect to OpenAI API")
      end
    end
  end

  describe '#extract_product_data' do
    before do
      allow(ENV).to receive(:[]).with('OPENAI_API_KEY').and_return('test-key')
    end

    context 'input validation' do
      it 'rejects blank HTML content' do
        result = extractor.extract_product_data('', sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("HTML content cannot be blank")
      end

      it 'rejects nil HTML content' do
        result = extractor.extract_product_data(nil, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("HTML content cannot be blank")
      end

      it 'rejects blank URL' do
        result = extractor.extract_product_data(sample_html, '')

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL cannot be blank")
      end

      it 'rejects nil URL' do
        result = extractor.extract_product_data(sample_html, nil)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL cannot be blank")
      end
    end

    context 'successful extraction' do
      before do
        allow(mock_client).to receive(:chat) do
          sleep(0.01) # Small delay to ensure measurable response time
          successful_response
        end
      end

      it 'successfully extracts structured product data' do
        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_a(Hash)
        expect(result[:data]['product']['name']).to eq("Test Product")
        expect(result[:data]['variants']).to be_an(Array)
        expect(result[:data]['variants'].size).to eq(1)
        expect(result[:data]['variants'][0]['price_cents']).to eq(1999)
        expect(result[:url]).to eq(sample_url)
        expect(result[:model_used]).to eq("gpt-3.5-turbo")
        expect(result[:errors]).to be_empty
        expect(result[:raw_response]).to eq(successful_json_response.to_json)
        expect(result[:response_time]).to be > 0
      end

      it 'makes request with correct parameters' do
        expect(mock_client).to receive(:chat).with(
          parameters: {
            model: "gpt-3.5-turbo",
            messages: array_including(
              hash_including(role: "system"),
              hash_including(role: "user")
            ),
            temperature: 0.1,
            max_tokens: 2000
          }
        ).and_return(successful_response)

        extractor.extract_product_data(sample_html, sample_url)
      end

      it 'includes URL in the prompt' do
        expect(mock_client).to receive(:chat) do |params|
          user_message = params[:parameters][:messages].find { |m| m[:role] == "user" }
          expect(user_message[:content]).to include(sample_url)
          successful_response
        end

        extractor.extract_product_data(sample_html, sample_url)
      end

      it 'truncates long HTML content' do
        long_html = 'a' * 10000 # Very long content
        
        expect(mock_client).to receive(:chat) do |params|
          user_message = params[:parameters][:messages].find { |m| m[:role] == "user" }
          # Content should be truncated
          expect(user_message[:content].length).to be < long_html.length
          successful_response
        end

        extractor.extract_product_data(long_html, sample_url)
      end
    end

    context 'API errors' do
      it 'handles quota exceeded errors' do
        allow(mock_client).to receive(:chat).and_raise(OpenAI::Error.new("Quota exceeded"))

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Quota exceeded: Check your OpenAI billing")
      end

      it 'handles permission errors' do
        allow(mock_client).to receive(:chat).and_raise(OpenAI::Error.new("Permission denied"))

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Permission denied: Check your API key permissions")
      end

      it 'handles general API errors' do
        allow(mock_client).to receive(:chat).and_raise(OpenAI::Error.new("API error"))

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("OpenAI API error: API error")
      end

      it 'handles JSON parsing errors' do
        allow(mock_client).to receive(:chat).and_raise(JSON::ParserError.new("Invalid JSON"))

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Invalid JSON response from OpenAI API")
      end

      it 'handles unexpected errors' do
        allow(mock_client).to receive(:chat).and_raise(StandardError.new("Unexpected error"))

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Unexpected error: StandardError - Unexpected error")
      end
    end

    context 'invalid API responses' do
      it 'handles missing content in response' do
        invalid_response = {
          "choices" => [
            {
              "message" => {}
            }
          ]
        }
        allow(mock_client).to receive(:chat).and_return(invalid_response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Invalid response format from OpenAI API")
      end

      it 'handles missing choices in response' do
        invalid_response = {}
        allow(mock_client).to receive(:chat).and_return(invalid_response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Invalid response format from OpenAI API")
      end
    end

    context 'JSON response parsing' do
      it 'handles valid JSON response' do
        valid_json = {
          "product" => { "name" => "Test Product" },
          "variants" => [{ "name" => "Test Variant", "price_cents" => 100, "currency" => "USD" }]
        }.to_json

        response = {
          "choices" => [{ "message" => { "content" => valid_json } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_a(Hash)
        expect(result[:errors]).to be_empty
      end

      it 'handles JSON with markdown formatting' do
        json_with_markdown = "```json\n#{successful_json_response.to_json}\n```"
        response = {
          "choices" => [{ "message" => { "content" => json_with_markdown } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_a(Hash)
      end

      it 'handles invalid JSON response' do
        invalid_json = "{ invalid json }"
        response = {
          "choices" => [{ "message" => { "content" => invalid_json } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include(match(/Invalid JSON response/))
      end

      it 'handles missing product section' do
        invalid_structure = { "variants" => [] }.to_json
        response = {
          "choices" => [{ "message" => { "content" => invalid_structure } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include("Missing or invalid 'product' section")
      end

      it 'handles missing variants section' do
        invalid_structure = { "product" => { "name" => "Test" } }.to_json
        response = {
          "choices" => [{ "message" => { "content" => invalid_structure } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include("Missing or invalid 'variants' section")
      end

      it 'validates variant data structure' do
        invalid_variant = {
          "product" => { "name" => "Test" },
          "variants" => [{ "name" => "Test", "price_cents" => "not_integer" }]
        }.to_json
        response = {
          "choices" => [{ "message" => { "content" => invalid_variant } }]
        }
        allow(mock_client).to receive(:chat).and_return(response)

        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:success]).to be true
        expect(result[:data]).to be_nil
        expect(result[:errors]).to include(match(/price_cents must be a non-negative integer/))
      end
    end

    context 'response structure' do
      before do
        allow(mock_client).to receive(:chat).and_return(successful_response)
      end

      it 'always returns expected keys' do
        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result).to have_key(:success)
        expect(result).to have_key(:data)
        expect(result).to have_key(:raw_response)
        expect(result).to have_key(:url)
        expect(result).to have_key(:model_used)
        expect(result).to have_key(:response_time)
        expect(result).to have_key(:errors)
      end

      it 'returns errors as an array' do
        result = extractor.extract_product_data(sample_html, sample_url)

        expect(result[:errors]).to be_an(Array)
      end
    end
  end

  describe 'configuration' do
    it 'uses default model' do
      expect(extractor.instance_variable_get(:@model)).to eq("gpt-3.5-turbo")
    end

    it 'uses default temperature' do
      expect(extractor.instance_variable_get(:@temperature)).to eq(0.1)
    end

    it 'uses default max tokens' do
      expect(extractor.instance_variable_get(:@max_tokens)).to eq(2000)
    end

    it 'allows custom configuration' do
      custom_extractor = AiContentExtractor.new(
        model: "gpt-4",
        temperature: 0.2,
        max_tokens: 2000
      )

      expect(custom_extractor.instance_variable_get(:@model)).to eq("gpt-4")
      expect(custom_extractor.instance_variable_get(:@temperature)).to eq(0.2)
      expect(custom_extractor.instance_variable_get(:@max_tokens)).to eq(2000)
    end
  end
end 
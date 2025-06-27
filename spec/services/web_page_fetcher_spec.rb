require 'rails_helper'

RSpec.describe WebPageFetcher, type: :service do
  let(:fetcher) { WebPageFetcher.new }
  let(:valid_url) { "https://example.com" }
  let(:mock_response) { double('response', body: '<html><head><title>Test</title></head><body>Test content</body></html>', code: 200, message: 'OK') }

  describe '#fetch' do
    context 'with valid URLs' do
      before do
        allow(WebPageFetcher).to receive(:get) do
          sleep(0.01) # Small delay to ensure measurable response time
          mock_response
        end
      end

      it 'successfully fetches content from a valid URL' do
        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be true
        expect(result[:content]).to eq(mock_response.body)
        expect(result[:url]).to eq(valid_url)
        expect(result[:status_code]).to eq(200)
        expect(result[:response_time]).to be > 0
        expect(result[:errors]).to be_empty
      end

      it 'includes response time measurement' do
        result = fetcher.fetch(valid_url)

        expect(result[:response_time]).to be_a(Float)
        expect(result[:response_time]).to be > 0
      end

      it 'returns the correct URL in the response' do
        result = fetcher.fetch(valid_url)

        expect(result[:url]).to eq(valid_url)
      end
    end

    context 'URL validation' do
      it 'rejects blank URLs' do
        result = fetcher.fetch("")

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL cannot be blank")
      end

      it 'rejects nil URLs' do
        result = fetcher.fetch(nil)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL cannot be blank")
      end

      it 'rejects non-HTTP/HTTPS URLs' do
        result = fetcher.fetch("ftp://example.com")

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL must use HTTP or HTTPS protocol")
      end

      it 'rejects malformed URLs' do
        result = fetcher.fetch("not-a-url")

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Invalid URL format")
      end

      it 'rejects URLs without host' do
        result = fetcher.fetch("https://")

        expect(result[:success]).to be false
        expect(result[:errors]).to include("URL must have a valid host")
      end

      it 'accepts valid HTTP URLs' do
        allow(WebPageFetcher).to receive(:get).and_return(mock_response)
        
        result = fetcher.fetch("http://example.com")

        expect(result[:success]).to be true
      end

      it 'accepts valid HTTPS URLs' do
        allow(WebPageFetcher).to receive(:get).and_return(mock_response)
        
        result = fetcher.fetch("https://example.com")

        expect(result[:success]).to be true
      end

      it 'accepts URLs with paths and query parameters' do
        allow(WebPageFetcher).to receive(:get).and_return(mock_response)
        
        result = fetcher.fetch("https://example.com/product?id=123")

        expect(result[:success]).to be true
      end
    end

    context 'HTTP error responses' do
      it 'handles 404 errors' do
        error_response = double('response', code: 404, message: 'Not Found')
        allow(WebPageFetcher).to receive(:get).and_return(error_response)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("HTTP 404: Not Found")
      end

      it 'handles 500 errors' do
        error_response = double('response', code: 500, message: 'Internal Server Error')
        allow(WebPageFetcher).to receive(:get).and_return(error_response)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("HTTP 500: Internal Server Error")
      end

      it 'handles 403 errors' do
        error_response = double('response', code: 403, message: 'Forbidden')
        allow(WebPageFetcher).to receive(:get).and_return(error_response)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("HTTP 403: Forbidden")
      end
    end

    context 'network errors' do
      it 'handles timeout errors' do
        allow(WebPageFetcher).to receive(:get).and_raise(::Timeout::Error.new)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Request timed out after 3 retries")
      end

      it 'handles connection errors' do
        allow(WebPageFetcher).to receive(:get).and_raise(SocketError.new)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Could not connect to example.com")
      end

      it 'handles connection refused errors' do
        allow(WebPageFetcher).to receive(:get).and_raise(Errno::ECONNREFUSED.new)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Could not connect to example.com")
      end
    end

    context 'empty responses' do
      it 'handles empty response bodies' do
        empty_response = double('response', body: '', code: 200, message: 'OK')
        allow(WebPageFetcher).to receive(:get).and_return(empty_response)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("No content received from server")
      end

      it 'handles nil response bodies' do
        empty_response = double('response', body: nil, code: 200, message: 'OK')
        allow(WebPageFetcher).to receive(:get).and_return(empty_response)

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("No content received from server")
      end
    end

    context 'retry behavior' do
      it 'retries on timeout errors' do
        call_count = 0
        allow(WebPageFetcher).to receive(:get) do
          call_count += 1
          if call_count <= 2
            raise ::Timeout::Error.new
          else
            mock_response
          end
        end
        allow(fetcher).to receive(:sleep) # Speed up test

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be true
        expect(call_count).to eq(3) # Initial attempt + 2 retries
      end

      it 'fails after max retries' do
        allow(WebPageFetcher).to receive(:get).and_raise(::Timeout::Error.new)
        allow(fetcher).to receive(:sleep) # Speed up test by not actually sleeping

        result = fetcher.fetch(valid_url)

        expect(result[:success]).to be false
        expect(result[:errors]).to include("Request timed out after 3 retries")
      end
    end

    context 'response structure' do
      before do
        allow(WebPageFetcher).to receive(:get).and_return(mock_response)
      end

      it 'always returns a hash with expected keys' do
        result = fetcher.fetch(valid_url)

        expect(result).to have_key(:success)
        expect(result).to have_key(:content)
        expect(result).to have_key(:url)
        expect(result).to have_key(:status_code)
        expect(result).to have_key(:response_time)
        expect(result).to have_key(:errors)
      end

      it 'returns errors as an array' do
        result = fetcher.fetch(valid_url)

        expect(result[:errors]).to be_an(Array)
      end
    end
  end

  describe 'configuration' do
    it 'sets appropriate timeout' do
      expect(WebPageFetcher.default_options[:timeout]).to eq(30)
    end

    it 'sets user agent header' do
      expect(WebPageFetcher.default_options[:headers]['User-Agent']).to include('Product Comparison Tool')
    end
  end
end 
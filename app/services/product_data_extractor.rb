class ProductDataExtractor
  def initialize
    @web_fetcher = WebPageFetcher.new
    @ai_extractor = AiContentExtractor.new
  end

  # Main entry point: URL -> HTML -> AI extraction
  def extract_from_url(url)
    start_time = Time.current

    # Step 1: Fetch web page content
    fetch_result = @web_fetcher.fetch(url)
    
    unless fetch_result[:success]
      return {
        success: false,
        url: url,
        stage: 'fetch',
        data: nil,
        processing_time: (Time.current - start_time).round(2),
        errors: fetch_result[:errors],
        details: {
          fetch_result: fetch_result
        }
      }
    end

    # Step 2: Extract product data using AI
    extraction_result = @ai_extractor.extract_product_data(
      fetch_result[:content], 
      url
    )

    unless extraction_result[:success]
      return {
        success: false,
        url: url,
        stage: 'extraction',
        data: nil,
        processing_time: (Time.current - start_time).round(2),
        errors: extraction_result[:errors],
        details: {
          fetch_result: fetch_result,
          extraction_result: extraction_result
        }
      }
    end

    # Step 3: Return successful result
    {
      success: true,
      url: url,
      stage: 'completed',
      data: extraction_result[:data],
      processing_time: (Time.current - start_time).round(2),
      errors: [],
      details: {
        fetch_result: fetch_result,
        extraction_result: extraction_result,
        content_length: fetch_result[:content]&.length || 0,
        model_used: extraction_result[:model_used]
      }
    }
  end

  # Test the complete pipeline with a simple connection check
  def test_pipeline
    start_time = Time.current

    # Test web fetching
    web_test = @web_fetcher.fetch("https://httpbin.org/html")
    unless web_test[:success]
      return {
        success: false,
        stage: 'web_fetch_test',
        errors: ["Web fetcher test failed: #{web_test[:errors].join(', ')}"],
        processing_time: (Time.current - start_time).round(2)
      }
    end

    # Test AI connection
    ai_test = @ai_extractor.test_connection
    unless ai_test[:success]
      return {
        success: false,
        stage: 'ai_connection_test',
        errors: ["AI extractor test failed: #{ai_test[:errors].join(', ')}"],
        processing_time: (Time.current - start_time).round(2)
      }
    end

    {
      success: true,
      stage: 'completed',
      message: "Pipeline test successful",
      processing_time: (Time.current - start_time).round(2),
      errors: [],
      details: {
        web_fetch_status: web_test[:status_code],
        web_fetch_time: web_test[:response_time],
        ai_connection_response: ai_test[:response]
      }
    }
  end

  # Health check for individual components
  def health_check
    {
      web_fetcher: {
        available: true,
        class: @web_fetcher.class.name
      },
      ai_extractor: {
        available: ENV['OPENAI_API_KEY'].present?,
        api_key_configured: ENV['OPENAI_API_KEY'].present?,
        class: @ai_extractor.class.name
      },
      overall_status: ENV['OPENAI_API_KEY'].present? ? 'ready' : 'missing_api_key'
    }
  end
end 
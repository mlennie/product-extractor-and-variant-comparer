class ProductDataExtractor
  def initialize
    @web_fetcher = WebPageFetcher.new
    @ai_extractor = AiContentExtractor.new
    @database_service = ProductDatabaseService.new
  end

  # Main entry point: URL -> HTML -> AI extraction -> Database save
  def extract_from_url(url)
    start_time = Time.current

    # Mark product as processing
    processing_result = @database_service.mark_product_as_processing(url)
    unless processing_result[:success]
      return build_error_result(url, 'database_setup', processing_result[:errors], start_time)
    end

    # Step 1: Fetch web page content
    fetch_result = @web_fetcher.fetch(url)
    unless fetch_result[:success]
      @database_service.mark_product_as_failed(url, "Failed to fetch webpage: #{fetch_result[:errors].join(', ')}")
      return build_error_result(url, 'fetch', fetch_result[:errors], start_time, fetch_result)
    end

    # Step 2: Extract product data using AI
    extraction_result = @ai_extractor.extract_product_data(fetch_result[:content], url)
    unless extraction_result[:success]
      @database_service.mark_product_as_failed(url, "Failed to extract data: #{extraction_result[:errors].join(', ')}")
      return build_error_result(url, 'extraction', extraction_result[:errors], start_time, fetch_result, extraction_result)
    end

    # Check if we have valid structured data
    unless extraction_result[:data].present?
      error_msg = "No structured data extracted from AI response"
      @database_service.mark_product_as_failed(url, error_msg)
      return build_error_result(url, 'data_validation', [error_msg], start_time, fetch_result, extraction_result)
    end

    # Step 3: Save to database
    save_result = @database_service.save_product_data(extraction_result[:data], url)
    unless save_result[:success]
      @database_service.mark_product_as_failed(url, "Failed to save data: #{save_result[:errors].join(', ')}")
      return build_error_result(url, 'database_save', save_result[:errors], start_time, fetch_result, extraction_result, save_result)
    end

    # Step 4: Return successful result with database records
    {
      success: true,
      product: save_result[:product],
      variants: save_result[:variants],
      best_value_variant: save_result[:best_value_variant],
      processing_time: (Time.current - start_time).round(2),
      errors: [],
      details: {
        fetch_result: {
          status_code: fetch_result[:status_code],
          content_length: fetch_result[:content]&.length || 0,
          response_time: fetch_result[:response_time]
        },
        extraction_result: {
          model_used: extraction_result[:model_used],
          response_time: extraction_result[:response_time],
          raw_response_length: extraction_result[:raw_response]&.length || 0
        },
        database_result: {
          variants_created: save_result[:variants]&.count || 0,
          processing_time: save_result[:processing_time]
        }
      }
    }
  end

  # Extract without saving to database (for testing/debugging)
  def extract_without_saving(url)
    start_time = Time.current

    # Step 1: Fetch web page content
    fetch_result = @web_fetcher.fetch(url)
    unless fetch_result[:success]
      return build_error_result(url, 'fetch', fetch_result[:errors], start_time, fetch_result)
    end

    # Step 2: Extract product data using AI
    extraction_result = @ai_extractor.extract_product_data(fetch_result[:content], url)
    unless extraction_result[:success]
      return build_error_result(url, 'extraction', extraction_result[:errors], start_time, fetch_result, extraction_result)
    end

    # Return extraction result without database save
    {
      success: true,
      url: url,
      stage: 'extraction_completed',
      extracted_data: extraction_result[:data],
      processing_time: (Time.current - start_time).round(2),
      errors: extraction_result[:errors],
      details: {
        fetch_result: fetch_result,
        extraction_result: extraction_result
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

    # Test database service
    database_test = test_database_service
    unless database_test[:success]
      return {
        success: false,
        stage: 'database_test',
        errors: ["Database service test failed: #{database_test[:errors].join(', ')}"],
        processing_time: (Time.current - start_time).round(2)
      }
    end

    {
      success: true,
      stage: 'completed',
      message: "Full pipeline test successful",
      processing_time: (Time.current - start_time).round(2),
      errors: [],
      details: {
        web_fetch_status: web_test[:status_code],
        web_fetch_time: web_test[:response_time],
        ai_connection_response: ai_test[:response],
        database_service: database_test[:message]
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
      database_service: {
        available: true,
        class: @database_service.class.name,
        database_connected: database_connected?
      },
      overall_status: determine_overall_status
    }
  end

  private

  def test_database_service
    begin
      # Ensure database connection and test with Product model
      ActiveRecord::Base.connection.reconnect! unless ActiveRecord::Base.connection.active?
      product_count = Product.count
      { success: true, message: "Database service operational (#{product_count} products)", errors: [] }
    rescue => e
      { success: false, message: "Database service failed", errors: [e.message] }
    end
  end

  def database_connected?
    # Force a database connection and test it with a simple query
    ActiveRecord::Base.connection.execute("SELECT 1")
    true
  rescue => e
    Rails.logger.debug "Database connection check failed: #{e.message}"
    false
  end

  def determine_overall_status
    return 'missing_api_key' unless ENV['OPENAI_API_KEY'].present?
    return 'database_error' unless database_connected?
    'ready'
  end

  def build_error_result(url, stage, errors, start_time, fetch_result = nil, extraction_result = nil, save_result = nil)
    {
      success: false,
      product: nil,
      variants: [],
      best_value_variant: nil,
      processing_time: (Time.current - start_time).round(2),
      errors: errors,
      details: {
        url: url,
        stage: stage,
        fetch_result: fetch_result,
        extraction_result: extraction_result,
        save_result: save_result
      }
    }
  end
end 
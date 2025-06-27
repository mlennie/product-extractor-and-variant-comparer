class AiContentExtractor
  # OpenAI model configuration
  DEFAULT_MODEL = "gpt-3.5-turbo"
  DEFAULT_TEMPERATURE = 0.1 # Low temperature for consistent extraction
  DEFAULT_MAX_TOKENS = 1000

  def initialize(model: DEFAULT_MODEL, temperature: DEFAULT_TEMPERATURE, max_tokens: DEFAULT_MAX_TOKENS)
    @model = model
    @temperature = temperature
    @max_tokens = max_tokens
    @client = OpenAI::Client.new
  end

  # Basic test method to verify OpenAI connectivity
  def test_connection
    result = make_request([
      {
        role: "user",
        content: "Respond with exactly: 'Connection successful'"
      }
    ])

    {
      success: result[:success],
      response: result[:success] ? result[:content] : nil,
      errors: result[:errors]
    }
  end

  # Extract product data from HTML content (basic implementation for Step 2)
  def extract_product_data(html_content, url)
    return error_result("HTML content cannot be blank") if html_content.blank?
    return error_result("URL cannot be blank") if url.blank?

    # Basic prompt for testing - will be enhanced in Step 3
    prompt = build_basic_extraction_prompt(html_content, url)
    
    result = make_request([
      {
        role: "system",
        content: "You are a helpful assistant that extracts product information from web pages."
      },
      {
        role: "user", 
        content: prompt
      }
    ])

    if result[:success]
      {
        success: true,
        data: result[:content],
        url: url,
        model_used: @model,
        errors: []
      }
    else
      {
        success: false,
        data: nil,
        url: url,
        model_used: @model,
        errors: result[:errors]
      }
    end
  end

  private

  def make_request(messages)
    # Check API key availability
    if ENV['OPENAI_API_KEY'].blank?
      return error_result("OpenAI API key not configured")
    end

    start_time = Time.current

    begin
      response = @client.chat(
        parameters: {
          model: @model,
          messages: messages,
          temperature: @temperature,
          max_tokens: @max_tokens
        }
      )

      if response.dig("choices", 0, "message", "content")
        {
          success: true,
          content: response.dig("choices", 0, "message", "content").strip,
          response_time: (Time.current - start_time).round(2),
          errors: []
        }
      else
        error_result("Invalid response format from OpenAI API")
      end

    rescue OpenAI::Error => e
      handle_openai_error(e)
    rescue Faraday::TimeoutError => e
      error_result("Request timeout: OpenAI API took too long to respond")
    rescue Faraday::ConnectionFailed => e
      error_result("Connection failed: Unable to connect to OpenAI API")
    rescue JSON::ParserError => e
      error_result("Invalid JSON response from OpenAI API")
    rescue => e
      error_result("Unexpected error: #{e.class.name} - #{e.message}")
    end
  end

  def handle_openai_error(error)
    # Handle different types of OpenAI errors based on message content
    message = error.message.to_s.downcase
    
    case 
    when message.include?('rate limit') || message.include?('too many requests')
      error_result("Rate limit exceeded: Please try again later")
    when message.include?('invalid') && message.include?('key')
      error_result("Authentication failed: Invalid API key")
    when message.include?('permission') || message.include?('forbidden')
      error_result("Permission denied: Check your API key permissions")  
    when message.include?('quota') || message.include?('billing')
      error_result("Quota exceeded: Check your OpenAI billing")
    else
      error_result("OpenAI API error: #{error.message}")
    end
  end

  def build_basic_extraction_prompt(html_content, url)
    # Truncate content to prevent token limit issues
    truncated_content = html_content[0, 4000] # Rough character limit
    
    <<~PROMPT
      I need you to analyze this product page and extract basic information.
      
      URL: #{url}
      
      HTML Content (truncated):
      #{truncated_content}
      
      Please identify if this appears to be a product page and extract any basic product information you can find.
      Respond with a simple summary of what you found.
    PROMPT
  end

  def error_result(message)
    {
      success: false,
      content: nil,
      response_time: 0,
      errors: [message]
    }
  end
end 
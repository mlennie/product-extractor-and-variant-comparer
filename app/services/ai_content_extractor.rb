class AiContentExtractor
  # OpenAI model configuration
  DEFAULT_MODEL = "gpt-3.5-turbo"
  DEFAULT_TEMPERATURE = 0.1 # Low temperature for consistent extraction
  DEFAULT_MAX_TOKENS = 2000 # Increased for structured responses

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

  # Extract structured product data from HTML content
  def extract_product_data(html_content, url)
    return error_result("HTML content cannot be blank") if html_content.blank?
    return error_result("URL cannot be blank") if url.blank?

    # Enhanced prompt for structured JSON responses
    prompt = build_structured_extraction_prompt(html_content, url)
    
    result = make_request([
      {
        role: "system",
        content: build_system_prompt
      },
      {
        role: "user", 
        content: prompt
      }
    ])

    if result[:success]
      # Parse and validate JSON response
      parsed_result = parse_json_response(result[:content])
      
      {
        success: true,
        data: parsed_result[:data],
        raw_response: result[:content],
        url: url,
        model_used: @model,
        response_time: result[:response_time],
        errors: parsed_result[:errors]
      }
    else
      {
        success: false,
        data: nil,
        raw_response: nil,
        url: url,
        model_used: @model,
        response_time: result[:response_time] || 0,
        errors: result[:errors]
      }
    end
  end

  private

  def build_system_prompt
    <<~SYSTEM_PROMPT
      You are an expert product data extraction AI. Your task is to analyze web page content and extract structured product information.

      CRITICAL: You must respond with valid JSON only. No additional text, explanations, or formatting.

      Extract the following information:
      1. Product name and description
      2. All available product variants (sizes, quantities, flavors, etc.)
      3. Pricing information for each variant
      4. Quantity information (numeric values and text descriptions)

      Response format must be exactly this JSON structure:
      {
        "product": {
          "name": "Product Name",
          "description": "Brief description"
        },
        "variants": [
          {
            "name": "Variant Name",
            "quantity_text": "12 oz",
            "quantity_numeric": 12.0,
            "price_cents": 299,
            "currency": "USD"
          }
        ]
      }

      Rules:
      - price_cents must be an integer (convert dollars to cents)
      - quantity_numeric should be a float representing the main quantity number
      - currency should be 3-letter code (USD, EUR, GBP, etc.)
      - If information is missing, use null for that field
      - Extract ALL variants found on the page
      - Be as accurate as possible with pricing and quantities
    SYSTEM_PROMPT
  end

  def build_structured_extraction_prompt(html_content, url)
    # Truncate content to prevent token limit issues
    truncated_content = html_content[0, 8000] # Increased limit for better extraction
    
    <<~PROMPT
      Extract product information from this web page:

      URL: #{url}

      HTML Content:
      #{truncated_content}

      Analyze the content and extract ALL product variants with their pricing and quantity information. 
      Respond with the exact JSON format specified in the system prompt.
    PROMPT
  end

  def parse_json_response(content)
    return { data: nil, errors: ["Empty response from AI"] } if content.blank?

    begin
      # Clean the response - remove any markdown formatting or extra text
      json_content = extract_json_from_response(content)
      
      parsed_data = JSON.parse(json_content)
      validation_result = validate_parsed_data(parsed_data)
      
      if validation_result[:valid]
        { data: parsed_data, errors: [] }
      else
        { data: nil, errors: validation_result[:errors] }
      end
      
    rescue JSON::ParserError => e
      { data: nil, errors: ["Invalid JSON response: #{e.message}"] }
    rescue => e
      { data: nil, errors: ["Error parsing response: #{e.message}"] }
    end
  end

  def extract_json_from_response(content)
    # Remove markdown code blocks if present
    content = content.gsub(/```json\s*/, '').gsub(/```\s*$/, '')
    
    # Try to find JSON object boundaries
    start_idx = content.index('{')
    end_idx = content.rindex('}')
    
    if start_idx && end_idx && end_idx > start_idx
      content[start_idx..end_idx]
    else
      content.strip
    end
  end

  def validate_parsed_data(data)
    errors = []
    
    # Check required structure
    unless data.is_a?(Hash)
      errors << "Response must be a JSON object"
      return { valid: false, errors: errors }
    end

    # Validate product section
    unless data['product'].is_a?(Hash)
      errors << "Missing or invalid 'product' section"
    else
      errors << "Product name is required" if data['product']['name'].blank?
    end

    # Validate variants section
    unless data['variants'].is_a?(Array)
      errors << "Missing or invalid 'variants' section"
    else
      data['variants'].each_with_index do |variant, index|
        validate_variant(variant, index, errors)
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  def validate_variant(variant, index, errors)
    prefix = "Variant #{index + 1}:"
    
    unless variant.is_a?(Hash)
      errors << "#{prefix} Must be an object"
      return
    end

    errors << "#{prefix} Name is required" if variant['name'].blank?
    
    if variant['price_cents'].present?
      unless variant['price_cents'].is_a?(Integer) && variant['price_cents'] >= 0
        errors << "#{prefix} price_cents must be a non-negative integer"
      end
    end

    if variant['quantity_numeric'].present?
      unless variant['quantity_numeric'].is_a?(Numeric) && variant['quantity_numeric'] > 0
        errors << "#{prefix} quantity_numeric must be a positive number"
      end
    end

    if variant['currency'].present?
      unless variant['currency'].is_a?(String) && variant['currency'].length == 3
        errors << "#{prefix} currency must be a 3-letter string"
      end
    end
  end

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

  def error_result(message)
    {
      success: false,
      content: nil,
      response_time: 0,
      errors: [message]
    }
  end
end 
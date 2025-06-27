class WebPageFetcher
  include HTTParty
  
  # Configuration
  default_timeout 30
  headers({
    'User-Agent' => 'Product Comparison Tool/1.0 (Mozilla/5.0 compatible)'
  })

  def initialize
    @max_retries = 3
    @retry_delay = 1 # seconds
  end

  def fetch(url)
    start_time = Time.current
    
    # Validate URL first
    validation_result = validate_url(url)
    return validation_result unless validation_result[:success]

    # Attempt to fetch with retries
    response = fetch_with_retries(url)
    
    {
      success: true,
      content: response.body,
      url: url,
      status_code: response.code,
      response_time: (Time.current - start_time).round(2),
      errors: []
    }
  rescue HTTPError, TimeoutError, ConnectionError, EmptyResponseError => e
    {
      success: false,
      content: nil,
      url: url,
      status_code: nil,
      response_time: (Time.current - start_time).round(2),
      errors: [e.message]
    }
  rescue => e
    {
      success: false,
      content: nil,
      url: url,
      status_code: nil,
      response_time: (Time.current - start_time).round(2),
      errors: ["Network error: #{e.class.name} - #{e.message}"]
    }
  end

  private

  def validate_url(url)
    return error_result("URL cannot be blank", url) if url.blank?
    
    # Check for clearly malformed URLs first
    if url !~ URI::DEFAULT_PARSER.make_regexp
      return error_result("Invalid URL format", url)
    end
    
    begin
      uri = URI.parse(url)
    rescue URI::InvalidURIError
      return error_result("Invalid URL format", url)
    end
    
    unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return error_result("URL must use HTTP or HTTPS protocol", url)
    end
    
    unless uri.host.present?
      return error_result("URL must have a valid host", url)
    end

    { success: true }
  end

  def fetch_with_retries(url)
    retries = 0
    
    begin
      response = self.class.get(url, {
        timeout: 30,
        follow_redirects: true,
        limit: 5 # redirect limit
      })
      
      # Check for HTTP errors
      if response.code >= 400
        raise HTTPError.new("HTTP #{response.code}: #{response.message}")
      end
      
      # Check for empty response
      if response.body.blank?
        raise EmptyResponseError.new("No content received from server")
      end
      
      response
    rescue ::Timeout::Error => e
      retries += 1
      if retries <= @max_retries
        sleep(@retry_delay * retries)
        retry
      else
        raise TimeoutError.new("Request timed out after #{@max_retries} retries")
      end
    rescue SocketError, Errno::ECONNREFUSED => e
      raise ConnectionError.new("Could not connect to #{URI.parse(url).host}")
    end
  end

  def error_result(message, url)
    {
      success: false,
      content: nil,
      url: url,
      status_code: nil,
      response_time: 0,
      errors: [message]
    }
  end

  # Custom error classes for better error handling
  class HTTPError < StandardError; end
  class TimeoutError < StandardError; end
  class ConnectionError < StandardError; end
  class EmptyResponseError < StandardError; end
end 
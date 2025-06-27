OpenAI.configure do |config|
  config.access_token = ENV.fetch('OPENAI_API_KEY', nil)
  config.log_errors = Rails.env.development?
  config.request_timeout = 30 # seconds
  config.extra_headers = {
    "User-Agent" => "ProductComparisonTool/1.0"
  }
end

# Verify API key is present in production
if Rails.env.production? && ENV['OPENAI_API_KEY'].blank?
  Rails.logger.error "OPENAI_API_KEY environment variable is not set"
end 
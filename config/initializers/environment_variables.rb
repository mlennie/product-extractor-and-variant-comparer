# Development environment variables verification
# The .env file is now loaded by dotenv-rails automatically

# Verify API key is present in development
if Rails.env.development?
  if ENV['OPENAI_API_KEY'].present?
    Rails.logger.info "✅ OpenAI API key is configured"
  else
    Rails.logger.warn "⚠️  OpenAI API key is not configured"
  end
end 
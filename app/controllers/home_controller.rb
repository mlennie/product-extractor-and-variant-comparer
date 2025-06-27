class HomeController < ApplicationController
  def index
  end

  def create
    @url = params[:url]
    
    # Basic URL validation
    if @url.blank?
      flash[:error] = "Please enter a URL"
      redirect_to root_path
      return
    end

    unless valid_url?(@url)
      flash[:error] = "Please enter a valid URL (must start with http:// or https://)"
      redirect_to root_path
      return
    end

    begin
      # Create extraction job record
      extraction_job = ExtractionJob.create!(
        url: @url,
        status: 'queued',
        progress: 0
      )
      
      # Enqueue background job for processing
      ProductExtractionJob.perform_later(extraction_job.id)
      
      # Show success message with job ID
      flash[:success] = "✅ Extraction job created! Your product data is being processed in the background. Job ID: ##{extraction_job.id}"
      redirect_to root_path
      
    rescue ActiveRecord::RecordInvalid => e
      # Handle validation errors from ExtractionJob
      flash[:error] = "Failed to create extraction job: #{e.record.errors.full_messages.join(', ')}"
      redirect_to root_path
      
    rescue => e
      # Handle any other unexpected errors
      Rails.logger.error "Error creating extraction job: #{e.message}"
      flash[:error] = "An unexpected error occurred while creating the extraction job. Please try again."
      redirect_to root_path
    end
  end

  private

  def valid_url?(url)
    uri = URI.parse(url)
    %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end
end

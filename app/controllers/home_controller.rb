class HomeController < ApplicationController
  def index
    if params[:job_id].present?
      @tracking_job = ExtractionJob.find_by(id: params[:job_id])
    end
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
      
      # Redirect to home page with job ID for real-time tracking
      redirect_to root_path(job_id: extraction_job.id)
      
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

  def job_status
    @extraction_job = ExtractionJob.find(params[:id])
    
    # Build response data
    response_data = {
      id: @extraction_job.id,
      status: @extraction_job.status,
      progress: @extraction_job.progress,
      status_display: @extraction_job.status_display,
      progress_display: @extraction_job.progress_display,
      url: @extraction_job.url,
      created_at: @extraction_job.created_at.strftime('%I:%M %p'),
      finished: @extraction_job.finished?
    }
    
    # Add additional data based on status
    if @extraction_job.completed? && @extraction_job.product
      response_data[:product] = {
        id: @extraction_job.product.id,
        name: @extraction_job.product.name,
        variants_count: @extraction_job.product.product_variants.count,
        best_value_variant: best_value_info(@extraction_job.product)
      }
      
      if @extraction_job.result_data
        response_data[:processing_time] = @extraction_job.result_data['processing_time']
      end
    elsif @extraction_job.failed?
      response_data[:error_message] = @extraction_job.error_message
    end
    
    render json: response_data
    
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Job not found' }, status: :not_found
  end

  private

  def valid_url?(url)
    uri = URI.parse(url)
    %w[http https].include?(uri.scheme)
  rescue URI::InvalidURIError
    false
  end
  
  def best_value_info(product)
    best_variant = product.best_value_variant
    return nil unless best_variant
    
    # Build price per unit display with unit information
    price_per_unit_display = if best_variant.formatted_price_per_unit != 'N/A' && best_variant.quantity_text.present?
      "#{best_variant.formatted_price_per_unit} per #{best_variant.quantity_text.gsub(/^\d+\s*/, '')}"
    else
      best_variant.formatted_price_per_unit
    end
    
    {
      id: best_variant.id,
      name: best_variant.name,
      price_display: best_variant.formatted_price,
      price_per_unit_display: price_per_unit_display
    }
  end
end

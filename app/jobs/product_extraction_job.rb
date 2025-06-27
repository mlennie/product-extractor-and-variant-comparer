class ProductExtractionJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ArgumentError

  def perform(extraction_job_id)
    extraction_job = ExtractionJob.find(extraction_job_id)
    
    # Skip if already processed
    return if extraction_job.finished?

    # Mark as processing
    extraction_job.mark_as_processing!
    
    # Initialize the data extractor
    extractor = ProductDataExtractor.new
    
    # Perform the extraction
    result = extractor.extract_from_url(extraction_job.url)
    
    if result[:success]
      # Mark as completed with the extracted product
      extraction_job.mark_as_completed!(
        result[:product], 
        {
          variants_count: result[:variants]&.count || 0,
          best_value_variant_id: result[:best_value_variant]&.id,
          processing_time: result[:processing_time],
          details: result[:details]
        }
      )
      
      Rails.logger.info "Successfully extracted product data for job #{extraction_job.id}: #{result[:product].name}"
    else
      # Mark as failed with error details
      error_message = result[:errors].join("; ")
      extraction_job.mark_as_failed!(error_message)
      
      Rails.logger.error "Failed to extract product data for job #{extraction_job.id}: #{error_message}"
    end
    
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "ExtractionJob #{extraction_job_id} not found: #{e.message}"
    raise # Re-raise to trigger retry logic
    
  rescue => e
    # Handle any unexpected errors
    Rails.logger.error "Unexpected error in ProductExtractionJob for job #{extraction_job_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    if extraction_job&.persisted?
      extraction_job.mark_as_failed!("Unexpected error: #{e.message}")
    end
    
    raise # Re-raise to trigger retry logic
  end
end 
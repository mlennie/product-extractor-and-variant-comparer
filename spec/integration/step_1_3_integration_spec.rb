require 'rails_helper'

RSpec.describe 'Step 1.3: Background Job Integration', type: :request do
  describe 'complete form-to-job pipeline' do
    let(:test_url) { 'https://example.com/test-product' }
    
    it 'successfully creates and processes an extraction job from form submission' do
      # Step 1: Submit the form via POST request
      expect {
        post '/extract', params: { url: test_url }
      }.to change(ExtractionJob, :count).by(1)
      
      # Step 2: Check the extraction job was created correctly
      extraction_job = ExtractionJob.last
      
      # Verify the response redirects correctly with job_id for Step 1.4 tracking
      expect(response).to redirect_to(root_path(job_id: extraction_job.id))
      expect(extraction_job.url).to eq(test_url)
      expect(extraction_job.status).to eq('queued')
      expect(extraction_job.progress).to eq(0)
      
      # Step 3: Mock the extractor for controlled testing
      mock_product = create(:product, name: 'Test Integration Product')
      mock_extractor = instance_double(ProductDataExtractor)
      allow(ProductDataExtractor).to receive(:new).and_return(mock_extractor)
      
      successful_result = {
        success: true,
        product: mock_product,
        variants: [],
        best_value_variant: nil,
        processing_time: 1.5,
        details: { test: 'integration' }
      }
      
      allow(mock_extractor).to receive(:extract_from_url).and_return(successful_result)
      
      # Step 4: Process the job synchronously
      expect {
        ProductExtractionJob.perform_now(extraction_job.id)
      }.not_to raise_error
      
      # Step 5: Verify the job completed successfully
      extraction_job.reload
      expect(extraction_job.status).to eq('completed')
      expect(extraction_job.progress).to eq(100)
      expect(extraction_job.product).to eq(mock_product)
      expect(extraction_job.result_data).to include('processing_time' => 1.5)
    end
    
    it 'handles job failures gracefully' do
      # Submit form to create job
      post '/extract', params: { url: test_url }
      extraction_job = ExtractionJob.last
      
      # Mock failure scenario
      mock_extractor = instance_double(ProductDataExtractor)
      allow(ProductDataExtractor).to receive(:new).and_return(mock_extractor)
      
      failed_result = {
        success: false,
        errors: ['Network timeout', 'Service unavailable']
      }
      
      allow(mock_extractor).to receive(:extract_from_url).and_return(failed_result)
      
      # Process the job
      ProductExtractionJob.perform_now(extraction_job.id)
      
      # Verify failure handling
      extraction_job.reload
      expect(extraction_job.status).to eq('failed')
      expect(extraction_job.error_message).to include('Network timeout')
      expect(extraction_job.error_message).to include('Service unavailable')
    end
    
    it 'validates URL format during job creation' do
      # Test invalid URLs are rejected before job creation
      expect {
        post '/extract', params: { url: 'invalid-url' }
      }.not_to change(ExtractionJob, :count)
      
      # Should redirect with error message
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include('Please enter a valid URL')
    end
    
    it 'enqueues background jobs correctly' do
      # Test that jobs are actually enqueued for background processing
      expect {
        post '/extract', params: { url: test_url }
      }.to have_enqueued_job(ProductExtractionJob)
      
      # Verify job was created and has correct properties
      job = ExtractionJob.last
      expect(job).to be_present
      expect(job.url).to eq(test_url)
    end
  end
  
  describe 'job processing edge cases' do
    let(:extraction_job) { create(:extraction_job, url: 'https://example.com') }
    
    it 'skips processing for already completed jobs' do
      extraction_job.update!(status: 'completed')
      
      # Mock extractor to verify it's not called
      mock_extractor = spy(ProductDataExtractor)
      allow(ProductDataExtractor).to receive(:new).and_return(mock_extractor)
      
      ProductExtractionJob.perform_now(extraction_job.id)
      
      # Verify extractor was not called
      expect(mock_extractor).not_to have_received(:extract_from_url)
      
      # Job should remain completed
      extraction_job.reload
      expect(extraction_job.status).to eq('completed')
    end
    
    it 'handles missing jobs gracefully' do
      non_existent_id = ExtractionJob.maximum(:id).to_i + 1000
      
      expect {
        ProductExtractionJob.new.perform(non_existent_id)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end 
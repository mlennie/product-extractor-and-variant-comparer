require 'rails_helper'

RSpec.describe "Step 1.4 - Real-time Progress Updates Integration", type: :request do
  describe "Complete real-time job tracking workflow" do
    it "follows complete workflow from form submission to real-time tracking" do
      # Step 1: Submit form and get redirected to tracking page
      expect {
        post "/extract", params: { url: "https://example.com/test-product" }
      }.to change(ExtractionJob, :count).by(1)
      
      job = ExtractionJob.last
      expect(response).to redirect_to(root_path(job_id: job.id))
      
      # Step 2: Load tracking page and verify initial state
      get root_path(job_id: job.id)
      expect(response).to have_http_status(:ok)
      
      # Verify tracking section is displayed
      expect(response.body).to include("job-tracking-section")
      expect(response.body).to include("data-job-id=\"#{job.id}\"")
      expect(response.body).to include("Processing Your Request")
      expect(response.body).to include("https://example.com/test-product")
      
      # Verify initial status display
      expect(response.body).to include("data-status=\"queued\"")
      expect(response.body).to include("Queued for processing")
      expect(response.body).to include("style=\"width: 0%\"")
      
      # Step 3: Poll job status endpoint and verify JSON response
      get job_status_path(job.id)
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      
      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        'id' => job.id,
        'status' => 'queued',
        'progress' => 0,
        'status_display' => 'Queued for processing',
        'progress_display' => '0%',
        'url' => 'https://example.com/test-product',
        'finished' => false
      )
      
      # Step 4: Simulate job processing states
      job.mark_as_processing!
      
      get job_status_path(job.id)
      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        'status' => 'processing',
        'status_display' => 'Extracting product data',
        'finished' => false
      )
      
      # Step 5: Simulate progress updates
      job.update_progress!(50)
      
      get job_status_path(job.id)
      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        'progress' => 50,
        'progress_display' => '50%'
      )
      
      # Step 6: Simulate job completion with product data
      product = create(:product, name: "Test Product from URL")
      variant = create(:product_variant, 
        product: product,
        name: "Standard Size",
        price_cents: 1999,
        quantity_numeric: 1.0,
        quantity_text: "1 piece"
      )
      
      result_data = { 
        'processing_time' => 4.2,
        'variants_extracted' => 1,
        'ai_confidence' => 0.95
      }
      
      job.mark_as_completed!(product, result_data)
      
      get job_status_path(job.id)
      json_response = JSON.parse(response.body)
      
      expect(json_response).to include(
        'status' => 'completed',
        'progress' => 100,
        'finished' => true,
        'processing_time' => 4.2
      )
      
      expect(json_response['product']).to include(
        'name' => 'Test Product from URL',
        'variants_count' => 1
      )
      
      expect(json_response['product']['best_value_variant']).to include(
        'name' => 'Standard Size',
        'price_display' => '$19.99',
        'price_per_unit_display' => '$19.99 per piece'
      )
    end

    it "handles job failure scenarios with error display" do
      # Create and fail a job
      job = create(:extraction_job, :processing, url: "https://invalid-site.com")
      job.mark_as_failed!("Connection timeout: Unable to fetch page content")
      
      # Test status endpoint with failure
      get job_status_path(job.id)
      expect(response).to have_http_status(:ok)
      
      json_response = JSON.parse(response.body)
      expect(json_response).to include(
        'status' => 'failed',
        'finished' => true,
        'error_message' => 'Connection timeout: Unable to fetch page content'
      )
      
      # Test tracking page display with failure
      get root_path(job_id: job.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-status=\"failed\"")
    end

    it "handles multiple job tracking scenarios" do
      # Create multiple jobs in different states
      queued_job = create(:extraction_job, url: "https://site1.com")
      processing_job = create(:extraction_job, :processing, url: "https://site2.com", progress: 75)
      
      product = create(:product, name: "Completed Product")
      completed_job = create(:extraction_job, :completed, url: "https://site3.com", product: product)
      
      # Test each job's status endpoint
      [queued_job, processing_job, completed_job].each do |job|
        get job_status_path(job.id)
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq(job.id)
        expect(json_response['status']).to eq(job.status)
        expect(json_response['finished']).to eq(job.finished?)
      end
      
      # Test tracking page for each job
      [queued_job, processing_job, completed_job].each do |job|
        get root_path(job_id: job.id)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-job-id=\"#{job.id}\"")
        expect(response.body).to include("data-status=\"#{job.status}\"")
      end
    end

    it "gracefully handles non-existent jobs" do
      # Test status endpoint with invalid job ID
      get job_status_path(99999)
      expect(response).to have_http_status(:not_found)
      
      json_response = JSON.parse(response.body)
      expect(json_response['error']).to eq('Job not found')
      
      # Test tracking page with invalid job ID (should not show tracking section)
      get root_path(job_id: 99999)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("data-job-id=")
    end

    it "includes JavaScript polling functionality in tracking page" do
      job = create(:extraction_job, :processing)
      
      get root_path(job_id: job.id)
      expect(response).to have_http_status(:ok)
      
      # Verify JavaScript polling code is included
      expect(response.body).to include("pollJobStatus")
      expect(response.body).to include("setInterval(pollJobStatus")
      expect(response.body).to include("fetch(`/jobs/${jobId}/status`)")
      expect(response.body).to include("updateJobStatus")
      expect(response.body).to include("showJobResults")
      expect(response.body).to include("showJobError")
      
      # Verify status icon mapping
      expect(response.body).to include("'queued': '⏳'")
      expect(response.body).to include("'processing': '🔄'")
      expect(response.body).to include("'completed': '✅'")
      expect(response.body).to include("'failed': '❌'")
    end

    it "includes proper CSS styling for job tracking" do
      job = create(:extraction_job, :processing)
      
      get root_path(job_id: job.id)
      expect(response).to have_http_status(:ok)
      
      # Verify key CSS classes are present
      expect(response.body).to include(".job-tracking-section")
      expect(response.body).to include(".progress-bar")
      expect(response.body).to include(".progress-fill")
      expect(response.body).to include(".status-badge")
      expect(response.body).to include(".job-results")
      expect(response.body).to include(".job-error")
      
      # Verify animations and transitions
      expect(response.body).to include("@keyframes shimmer")
      expect(response.body).to include("@keyframes pulse")
      expect(response.body).to include("animation: pulse 2s infinite")
      
      # Verify responsive design
      expect(response.body).to include("@media (max-width: 768px)")
    end
  end

  describe "Error handling and edge cases" do
    it "handles job creation errors gracefully" do
      # Force a job creation error
      allow(ExtractionJob).to receive(:create!).and_raise(
        ActiveRecord::RecordInvalid.new(ExtractionJob.new)
      )
      
      post "/extract", params: { url: "https://example.com" }
      expect(response).to redirect_to(root_path)
      
      follow_redirect!
      expect(response.body).to include("Failed to create extraction job")
    end

    it "handles background job enqueueing" do
      expect {
        post "/extract", params: { url: "https://example.com" }
      }.to have_enqueued_job(ProductExtractionJob)
    end
  end
end 
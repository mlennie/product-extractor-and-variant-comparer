require 'rails_helper'

RSpec.describe "Homes", type: :request do
  describe "GET /" do
    it "returns http success" do
      get "/"
      expect(response).to have_http_status(:success)
    end

    it "displays the product extraction form" do
      get "/"
      expect(response.body).to include("AI Product Comparison Tool")
      expect(response.body).to include("Product URL")
      expect(response.body).to include("Extract Product Data")
    end

    it "includes proper form attributes" do
      get "/"
      expect(response.body).to include('action="/extract"')
      expect(response.body).to include('method="post"')
      expect(response.body).to include('type="url"')
      expect(response.body).to include('name="url"')
    end
  end

  describe "POST /extract" do
    context "with valid URL" do
      it "accepts valid http URL and creates extraction job" do
        expect {
          post "/extract", params: { url: "http://example.com" }
        }.to change(ExtractionJob, :count).by(1)
        
        job = ExtractionJob.last
        expect(response).to redirect_to(root_path(job_id: job.id))
        
        # Check the created job
        expect(job.url).to eq("http://example.com")
        expect(job.status).to eq("queued")
        expect(job.progress).to eq(0)
      end

      it "accepts valid https URL and creates extraction job" do
        expect {
          post "/extract", params: { url: "https://example.com/product" }
        }.to change(ExtractionJob, :count).by(1)
        
        job = ExtractionJob.last
        expect(response).to redirect_to(root_path(job_id: job.id))
        
        # Check the created job
        expect(job.url).to eq("https://example.com/product")
        expect(job.status).to eq("queued")
      end
      
      it "enqueues background job for processing" do
        expect {
          post "/extract", params: { url: "https://example.com" }
        }.to have_enqueued_job(ProductExtractionJob)
      end
    end

    context "with invalid URL" do
      it "rejects empty URL" do
        post "/extract", params: { url: "" }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Please enter a URL")
      end

      it "rejects nil URL" do
        post "/extract", params: {}
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Please enter a URL")
      end

      it "rejects URL without protocol" do
        post "/extract", params: { url: "example.com" }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Please enter a valid URL")
      end

      it "rejects invalid URL format" do
        post "/extract", params: { url: "not-a-url" }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Please enter a valid URL")
      end

      it "rejects unsupported protocol" do
        post "/extract", params: { url: "ftp://example.com" }
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Please enter a valid URL")
      end
    end

    context "job tracking redirects" do
      it "redirects to home page with job_id for valid URL" do
        post "/extract", params: { url: "https://example.com" }
        job = ExtractionJob.last
        expect(response).to redirect_to(root_path(job_id: job.id))
        expect(response.location).to include("job_id=#{job.id}")
      end

      it "displays error flash for invalid URL" do
        post "/extract", params: { url: "invalid" }
        expect(flash[:error]).to include("Please enter a valid URL")
      end
      
      it "displays error flash when job creation fails" do
        # Force a validation error by creating an invalid job
        allow(ExtractionJob).to receive(:create!).and_raise(
          ActiveRecord::RecordInvalid.new(ExtractionJob.new.tap { |job| job.errors.add(:url, "is invalid") })
        )
        
        post "/extract", params: { url: "https://example.com" }
        expect(flash[:error]).to include("Failed to create extraction job")
        expect(flash[:error]).to include("Url is invalid")
      end
    end
  end

  describe "form display features" do
    before { get "/" }

    it "includes feature descriptions" do
      expect(response.body).to include("AI-Powered")
      expect(response.body).to include("Best Value Analysis") 
      expect(response.body).to include("Real-time Processing")
    end

    it "includes responsive styling" do
      expect(response.body).to include("@media (max-width: 768px)")
    end

    it "includes proper form validation attributes" do
      expect(response.body).to include('required')
      expect(response.body).to include('pattern="https?://.+"')
    end
  end

  describe "GET /jobs/:id/status" do
    let(:extraction_job) { create(:extraction_job, :processing) }

    context "with valid job ID" do
      it "returns job status as JSON" do
        get job_status_path(extraction_job.id)
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/json')
        
        json_response = JSON.parse(response.body)
        expect(json_response['id']).to eq(extraction_job.id)
        expect(json_response['status']).to eq('processing')
        expect(json_response['progress']).to eq(extraction_job.progress)
        expect(json_response['status_display']).to eq('Extracting product data')
        expect(json_response['progress_display']).to eq("#{extraction_job.progress}%")
        expect(json_response['url']).to eq(extraction_job.url)
        expect(json_response['finished']).to eq(false)
      end

      it "includes product data when job is completed" do
        product = create(:product, name: "Test Product")
        variant1 = create(:product_variant, product: product, name: "Small Size", 
                          price_cents: 1299, quantity_numeric: 1.0, quantity_text: "1 piece")
        variant2 = create(:product_variant, product: product, name: "Large Size", 
                          price_cents: 2399, quantity_numeric: 2.0, quantity_text: "2 pieces")
        result_data = { 'processing_time' => 3.5 }
        
        completed_job = create(:extraction_job, :completed, product: product, result_data: result_data)
        
        get job_status_path(completed_job.id)
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['finished']).to eq(true)
        expect(json_response['product']).to be_present
        expect(json_response['product']['name']).to eq("Test Product")
        expect(json_response['product']['variants_count']).to eq(2)
        expect(json_response['product']['best_value_variant']).to be_present
        expect(json_response['processing_time']).to eq(3.5)
        
        # Test enhanced data structures
        expect(json_response['product']['variants']).to be_present
        expect(json_response['product']['variants'].length).to eq(2)
        expect(json_response['product']['price_range']).to be_present
        expect(json_response['product']['value_analysis']).to be_present
        
        # Test detailed variant data
        variant_data = json_response['product']['variants'].first
        expect(variant_data).to include('id', 'name', 'price_display', 'quantity_text', 
                                       'price_per_unit_display', 'is_best_value', 'value_rank')
        
        # Test price range data
        price_range = json_response['product']['price_range']
        expect(price_range).to include('min_price_display', 'max_price_display', 'price_spread_display')
        
        # Test value analysis data
        value_analysis = json_response['product']['value_analysis']
        expect(value_analysis).to include('best_value_display', 'worst_value_display', 
                                        'max_savings_display', 'max_savings_percentage')
      end

      it "includes error message when job failed" do
        failed_job = create(:extraction_job, :failed, error_message: "URL could not be fetched")
        
        get job_status_path(failed_job.id)
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['finished']).to eq(true)
        expect(json_response['error_message']).to eq("URL could not be fetched")
      end

      it "returns correct status for queued job" do
        queued_job = create(:extraction_job)  # Default status is 'queued'
        
        get job_status_path(queued_job.id)
        
        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        
        expect(json_response['status']).to eq('queued')
        expect(json_response['status_display']).to eq('Queued for processing')
        expect(json_response['finished']).to eq(false)
      end
    end

    context "with invalid job ID" do
      it "returns 404 for non-existent job" do
        get job_status_path(99999)
        
        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Job not found')
      end
    end
  end

  describe "GET / with job_id parameter" do
    context "with valid job_id" do
      it "displays job tracking section for existing job" do
        job = create(:extraction_job, :processing, url: "https://example.com/long-url-that-should-be-truncated")
        
        get root_path, params: { job_id: job.id }
        
        expect(response).to have_http_status(:success)
        expect(response.body).to include('data-controller="job-tracker"')
        expect(response.body).to include("data-job-tracker-job-id-value=\"#{job.id}\"")
        expect(response.body).to include('Processing Your Request')
        expect(response.body).to include(job.url)
      end

      it "includes progress bar with current progress" do
        job = create(:extraction_job, :processing, progress: 45)
        
        get root_path(job_id: job.id)
        
        expect(response.body).to include("progress-fill")
        expect(response.body).to include("style=\"width: 45%\"")
        expect(response.body).to include("45%")
      end

      it "includes status badge with current status" do
        job = create(:extraction_job, :processing)
        
        get root_path(job_id: job.id)
        
        expect(response.body).to include("data-status=\"processing\"")
        expect(response.body).to include("Extracting product data")
      end
    end

    context "with invalid job_id" do
      it "does not display tracking section for non-existent job" do
        get root_path(job_id: 99999)
        
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("data-job-id=")
        expect(response.body).not_to include("Processing Your Request")
      end
    end

    context "without job_id parameter" do
      it "displays normal home page without tracking section" do
        get root_path
        
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("data-job-id=")
        expect(response.body).to include("AI Product Comparison Tool")
        expect(response.body).to include("extraction-form-container")
      end
    end
  end

  describe "GET /jobs/:id/export" do
    let(:product) { create(:product, name: "Test Export Product") }
    let(:completed_job) { create(:extraction_job, :completed, product: product) }
    
    before do
      create(:product_variant, product: product, name: "Variant 1", 
             price_cents: 1000, quantity_numeric: 1.0, quantity_text: "1 piece")
      create(:product_variant, product: product, name: "Variant 2", 
             price_cents: 2000, quantity_numeric: 2.0, quantity_text: "2 pieces")
    end

    context "with completed job" do
      it "exports CSV format" do
        get export_results_path(completed_job.id, format: 'csv')
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).to include('.csv')
        
        csv_content = response.body
        expect(csv_content).to include('Variant Name')
        expect(csv_content).to include('Variant 1')
        expect(csv_content).to include('Variant 2')
        expect(csv_content).to include('$10.00')
        expect(csv_content).to include('$20.00')
      end

      it "exports JSON format" do
        get export_results_path(completed_job.id, format: 'json')
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/json')
        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Disposition']).to include('.json')
        
        json_content = JSON.parse(response.body)
        expect(json_content).to have_key('extraction_job')
        expect(json_content).to have_key('product')
        expect(json_content['product']).to have_key('variants')
        expect(json_content['product']['variants'].length).to eq(2)
      end

      it "defaults to CSV when no format specified" do
        get export_results_path(completed_job.id)
        
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/csv')
      end
    end

    context "with incomplete job" do
      let(:processing_job) { create(:extraction_job, :processing) }

      it "redirects with error for processing job" do
        get export_results_path(processing_job.id)
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Results not available for export')
      end
    end

    context "with invalid job ID" do
      it "redirects with error for non-existent job" do
        get export_results_path(99999)
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Job not found')
      end
    end

    context "with invalid format" do
      it "redirects with error for unsupported format" do
        get export_results_path(completed_job.id, format: 'xml')
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('Invalid export format')
      end
    end
  end

  describe "POST /check_url" do
    let(:existing_product) { create(:product, :with_variants, url: "https://example.com/existing") }
    
    context "with valid URL that has existing product" do
      it "returns existing product information" do
        post check_url_path, params: { url: existing_product.url }, as: :json
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response["exists"]).to be true
        expect(json_response["product"]["id"]).to eq(existing_product.id)
        expect(json_response["product"]["name"]).to eq(existing_product.name)
        expect(json_response["product"]["status"]).to eq(existing_product.status)
        expect(json_response["product"]["variants_count"]).to eq(existing_product.product_variants.count)
      end
    end
    
    context "with valid URL that has no existing product" do
      it "returns exists false" do
        post check_url_path, params: { url: "https://newurl.com/product" }, as: :json
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response["exists"]).to be false
      end
    end
    
    context "with invalid URL" do
      it "returns error for invalid URL" do
        post check_url_path, params: { url: "invalid-url" }, as: :json
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response["exists"]).to be false
        expect(json_response["error"]).to eq("Invalid URL")
      end
    end
    
    context "with blank URL" do
      it "returns error for blank URL" do
        post check_url_path, params: { url: "" }, as: :json
        
        expect(response).to have_http_status(:ok)
        
        json_response = JSON.parse(response.body)
        expect(json_response["exists"]).to be false
        expect(json_response["error"]).to eq("Invalid URL")
      end
    end
  end

  describe "Enhanced POST /extract with update messaging" do
    let(:existing_product) { create(:product, url: "https://example.com/existing") }
    
    context "when URL already has an existing product" do
      it "shows update message instead of creation message" do
        post extract_path, params: { url: existing_product.url }
        
        expect(response).to redirect_to(root_path(job_id: ExtractionJob.last.id))
        follow_redirect!
        
        expect(response.body).to include("🔄 Updating existing product data for this URL")
        expect(response.body).to include("Previous data will be replaced with fresh results")
      end
    end
    
    context "when URL is new" do
      it "shows creation message" do
        post extract_path, params: { url: "https://newproduct.com/item" }
        
        expect(response).to redirect_to(root_path(job_id: ExtractionJob.last.id))
        follow_redirect!
        
        expect(response.body).to include("✅ Product extraction started!")
        expect(response.body).not_to include("Updating existing product")
      end
    end
  end
end

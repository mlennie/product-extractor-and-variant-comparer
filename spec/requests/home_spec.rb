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
        
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Extraction job created!")
        expect(response.body).to include("Job ID:")
        
        # Check the created job
        job = ExtractionJob.last
        expect(job.url).to eq("http://example.com")
        expect(job.status).to eq("queued")
        expect(job.progress).to eq(0)
      end

      it "accepts valid https URL and creates extraction job" do
        expect {
          post "/extract", params: { url: "https://example.com/product" }
        }.to change(ExtractionJob, :count).by(1)
        
        expect(response).to redirect_to(root_path)
        follow_redirect!
        expect(response.body).to include("Extraction job created!")
        
        # Check the created job
        job = ExtractionJob.last
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

    context "flash messages" do
      it "displays success flash for valid URL with job creation" do
        post "/extract", params: { url: "https://example.com" }
        expect(flash[:success]).to include("Extraction job created!")
        expect(flash[:success]).to include("Job ID:")
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
end

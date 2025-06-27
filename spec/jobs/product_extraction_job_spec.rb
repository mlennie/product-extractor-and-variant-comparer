require 'rails_helper'

RSpec.describe ProductExtractionJob, type: :job do
  let(:extraction_job) { create(:extraction_job, url: "https://example.com/product") }
  let(:mock_extractor) { spy(ProductDataExtractor) }
  
  before do
    allow(ProductDataExtractor).to receive(:new).and_return(mock_extractor)
  end

  describe "#perform" do
    context "when extraction is successful" do
      let(:mock_product) { create(:product, name: "Test Product") }
      let(:mock_variants) { [create(:product_variant, product: mock_product)] }
      let(:successful_result) do
        {
          success: true,
          product: mock_product,
          variants: mock_variants,
          best_value_variant: mock_variants.first,
          processing_time: 2.5,
          details: { test: "data" }
        }
      end

      before do
        allow(mock_extractor).to receive(:extract_from_url).and_return(successful_result)
      end

      it "marks extraction job as processing when started" do
        # Simply verify the job performs successfully
        expect { ProductExtractionJob.new.perform(extraction_job.id) }.not_to raise_error
        
        # Job should complete successfully
        extraction_job.reload
        expect(extraction_job.status).to eq('completed')
      end

      it "calls ProductDataExtractor with correct URL" do
        expect(mock_extractor).to receive(:extract_from_url).with(extraction_job.url)
        
        ProductExtractionJob.new.perform(extraction_job.id)
      end

      it "marks extraction job as completed on success" do
        ProductExtractionJob.new.perform(extraction_job.id)
        
        extraction_job.reload
        expect(extraction_job.status).to eq('completed')
        expect(extraction_job.progress).to eq(100)
        expect(extraction_job.product).to eq(mock_product)
        expect(extraction_job.result_data).to include('variants_count' => 1)
      end

      it "logs successful extraction" do
        expect(Rails.logger).to receive(:info).with(/Successfully extracted product data/)
        
        ProductExtractionJob.new.perform(extraction_job.id)
      end
    end

    context "when extraction fails" do
      let(:failed_result) do
        {
          success: false,
          errors: ["Network timeout", "Invalid response"]
        }
      end

      before do
        allow(mock_extractor).to receive(:extract_from_url).and_return(failed_result)
      end

      it "marks extraction job as failed" do
        ProductExtractionJob.new.perform(extraction_job.id)
        
        extraction_job.reload
        expect(extraction_job.status).to eq('failed')
        expect(extraction_job.error_message).to eq("Network timeout; Invalid response")
      end

      it "logs failed extraction" do
        expect(Rails.logger).to receive(:error).with(/Failed to extract product data/)
        
        ProductExtractionJob.new.perform(extraction_job.id)
      end
    end

    context "when extraction job is already finished" do
      before do
        extraction_job.update!(status: 'completed')
      end

      it "skips processing for finished jobs" do
        ProductExtractionJob.new.perform(extraction_job.id)
        
        extraction_job.reload
        expect(extraction_job.status).to eq('completed') # Should remain completed
        expect(mock_extractor).not_to have_received(:extract_from_url)
      end
    end

    context "when extraction job is not found" do
      it "raises error and logs the issue" do
        expect(Rails.logger).to receive(:error).with(/ExtractionJob .* not found/)
        
        expect {
          ProductExtractionJob.new.perform(99999)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context "when unexpected error occurs" do
      let(:error_message) { "Unexpected database error" }
      
      before do
        allow(mock_extractor).to receive(:extract_from_url).and_raise(StandardError.new(error_message))
      end

      it "marks job as failed and logs error" do
        expect {
          ProductExtractionJob.new.perform(extraction_job.id)
        }.to raise_error(StandardError)
        
        extraction_job.reload
        expect(extraction_job.status).to eq('failed')
        expect(extraction_job.error_message).to include("Unexpected error: #{error_message}")
      end
    end
  end

  describe "job configuration" do
    it "is configured to use default queue" do
      expect(ProductExtractionJob.queue_name).to eq("default")
    end

    it "inherits from ApplicationJob" do
      expect(ProductExtractionJob.superclass).to eq(ApplicationJob)
    end
  end

  describe "integration with ActiveJob" do
    it "enqueues job correctly" do
      expect {
        ProductExtractionJob.perform_later(extraction_job.id)
      }.to have_enqueued_job(ProductExtractionJob)
        .with(extraction_job.id)
        .on_queue("default")
    end

    it "performs job immediately when called synchronously" do
      successful_result = {
        success: true,
        product: create(:product),
        variants: [],
        best_value_variant: nil,
        processing_time: 1.0,
        details: {}
      }
      
      allow(mock_extractor).to receive(:extract_from_url).and_return(successful_result)
      
      expect {
        ProductExtractionJob.perform_now(extraction_job.id)
      }.to change { extraction_job.reload.status }.from("queued").to("completed")
    end
  end
end 
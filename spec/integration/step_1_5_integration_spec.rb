require 'rails_helper'

RSpec.describe "Step 1.5 - Enhanced Results Display & User Experience Integration", type: :request do
  describe "Enhanced results display workflow" do
    let(:product) { create(:product, name: "Premium Headphones Collection") }
    let(:completed_job) { create(:extraction_job, :completed, product: product, 
                                result_data: { 'processing_time' => 4.2 }) }

    before do
      # Create multiple variants with different value propositions
      create(:product_variant, product: product, name: "Basic Model", 
             price_cents: 5999, quantity_numeric: 1.0, quantity_text: "1 unit")
      create(:product_variant, product: product, name: "Pro Model", 
             price_cents: 9999, quantity_numeric: 1.0, quantity_text: "1 unit")
      create(:product_variant, product: product, name: "Bulk Pack (3-units)", 
             price_cents: 15999, quantity_numeric: 3.0, quantity_text: "3 units")
      create(:product_variant, product: product, name: "Enterprise Pack (5-units)", 
             price_cents: 24999, quantity_numeric: 5.0, quantity_text: "5 units")
    end

    it "provides comprehensive enhanced job status data" do
      get job_status_path(completed_job.id)
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      
      # Test basic job data
      expect(json_response['status']).to eq('completed')
      expect(json_response['finished']).to eq(true)
      
      # Test enhanced product data structure
      product_data = json_response['product']
      expect(product_data['name']).to eq("Premium Headphones Collection")
      expect(product_data['variants_count']).to eq(4)
      
      # Test detailed variants array
      variants = product_data['variants']
      expect(variants.length).to eq(4)
      
      variants.each do |variant|
        expect(variant).to include(
          'id', 'name', 'price_cents', 'price_display', 'quantity_text',
          'quantity_numeric', 'price_per_unit_cents', 'price_per_unit_display',
          'is_best_value', 'value_rank', 'savings_vs_worst'
        )
      end
      
      # Test price range information
      price_range = product_data['price_range']
      expect(price_range).to include(
        'min_price', 'max_price', 'min_price_display', 'max_price_display',
        'price_spread', 'price_spread_display'
      )
      expect(price_range['min_price']).to eq(5999)
      expect(price_range['max_price']).to eq(24999)
      expect(price_range['min_price_display']).to eq('$59.99')
      expect(price_range['max_price_display']).to eq('$249.99')
      
      # Test value analysis
      value_analysis = product_data['value_analysis']
      expect(value_analysis).to include(
        'best_value_cents', 'worst_value_cents', 'best_value_display', 
        'worst_value_display', 'max_savings_cents', 'max_savings_display',
        'max_savings_percentage', 'variants_with_savings'
      )
      
      # Test best value identification (Enterprise Pack should be best per unit)
      best_variant = variants.find { |v| v['is_best_value'] }
      expect(best_variant['name']).to eq('Enterprise Pack (5-units)')
      expect(best_variant['value_rank']).to eq(1)
      
      # Test savings calculations
      variants.each do |variant|
        if variant['savings_vs_worst']
          savings = variant['savings_vs_worst']
          expect(savings).to include('savings_cents', 'savings_display', 'savings_percentage')
        end
      end
    end

    it "supports CSV export functionality" do
      get export_results_path(completed_job.id, format: 'csv')
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('text/csv')
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Disposition']).to include('.csv')
      
      csv_content = response.body
      lines = csv_content.split("\n")
      
      # Test header row
      header = lines.first
      expect(header).to include('Variant Name', 'Price', 'Quantity', 'Price Per Unit', 
                               'Value Rank', 'Best Value', 'Savings vs Worst', 'Savings %')
      
      # Test data rows
      expect(lines.length).to eq(5) # Header + 4 variants
      expect(csv_content).to include('Basic Model')
      expect(csv_content).to include('Pro Model')
      expect(csv_content).to include('Bulk Pack (3-units)')
      expect(csv_content).to include('Enterprise Pack (5-units)')
      expect(csv_content).to include('$59.99')
      expect(csv_content).to include('$99.99')
    end

    it "supports JSON export functionality" do
      get export_results_path(completed_job.id, format: 'json')
      
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include('application/json')
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Disposition']).to include('.json')
      
      export_data = JSON.parse(response.body)
      
      # Test extraction job data
      job_data = export_data['extraction_job']
      expect(job_data).to include('id', 'url', 'extracted_at', 'processing_time')
      expect(job_data['processing_time']).to eq(4.2)
      
      # Test product data
      product_data = export_data['product']
      expect(product_data['name']).to eq('Premium Headphones Collection')
      expect(product_data['variants_count']).to eq(4)
      expect(product_data['variants'].length).to eq(4)
      expect(product_data).to have_key('price_range')
      expect(product_data).to have_key('value_analysis')
    end

    it "includes enhanced UI elements in tracking page" do
      get root_path(job_id: completed_job.id)
      
      expect(response).to have_http_status(:ok)
      
      # Test CSS for enhanced results
      expect(response.body).to include('.results-header')
      expect(response.body).to include('.export-actions')
      expect(response.body).to include('.value-analysis')
      expect(response.body).to include('.variants-table')
      expect(response.body).to include('.best-badge')
      
      # Test enhanced error display CSS
      expect(response.body).to include('.error-message')
      expect(response.body).to include('.technical-details')
      expect(response.body).to include('.error-actions')
      expect(response.body).to include('.btn-retry')
      
      # Test JavaScript functions (updated for current implementation)
      expect(response.body).to include('exportResults')
      expect(response.body).to include('sortTable')
      expect(response.body).to include('shareResults')
      expect(response.body).to include('retryExtraction')
      expect(response.body).to include('reportIssue')
      
      # Test responsive design CSS
      expect(response.body).to include('@media (max-width: 768px)')
      expect(response.body).to include('@media (max-width: 640px)')
    end
    
    it "displays enhanced error messages for failed jobs" do
      failed_job = create(:extraction_job, :failed, error_message: "HTTP 403: Forbidden")
      
      get root_path(job_id: failed_job.id)
      
      expect(response).to have_http_status(:ok)
      
      # Verify error display elements are present (updated for Stimulus targets)
      expect(response.body).to include('data-job-tracker-target="error"')
      
      # Test that user-friendly error message functionality exists
      expect(response.body).to include('retryExtraction')
      expect(response.body).to include('reportIssue')
    end
  end

  describe "Export functionality edge cases" do
    let(:test_product) { create(:product, name: "Edge Case Product") }
    let(:test_completed_job) { create(:extraction_job, :completed, product: test_product) }

    before do
      create(:product_variant, product: test_product, name: "Test Variant", 
             price_cents: 1000, quantity_numeric: 1.0, quantity_text: "1 unit")
    end

    it "handles job without product gracefully" do
      failed_job = create(:extraction_job, :failed, error_message: "Extraction failed")
      
      get export_results_path(failed_job.id)
      
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Results not available for export')
    end

    it "handles processing job export attempts" do
      processing_job = create(:extraction_job, :processing)
      
      get export_results_path(processing_job.id, format: 'json')
      
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Results not available for export')
    end

    it "rejects invalid export formats" do
      get export_results_path(test_completed_job.id, format: 'xml')
      
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Invalid export format')
    end
  end

  describe "Value analysis accuracy" do
    let(:product) { create(:product, name: "Value Test Product") }
    let(:job) { create(:extraction_job, :completed, product: product) }

    before do
      # Create variants with known value relationships
      create(:product_variant, product: product, name: "Expensive Single", 
             price_cents: 2000, quantity_numeric: 1.0, quantity_text: "1 item")  # $20/item
      create(:product_variant, product: product, name: "Medium Bulk", 
             price_cents: 3000, quantity_numeric: 2.0, quantity_text: "2 items") # $15/item  
      create(:product_variant, product: product, name: "Best Value Pack", 
             price_cents: 4000, quantity_numeric: 4.0, quantity_text: "4 items") # $10/item (best)
      create(:product_variant, product: product, name: "Terrible Deal", 
             price_cents: 5000, quantity_numeric: 2.0, quantity_text: "2 items") # $25/item (worst)
    end

    it "correctly identifies best and worst values" do
      get job_status_path(job.id)
      
      json_response = JSON.parse(response.body)
      variants = json_response['product']['variants']
      value_analysis = json_response['product']['value_analysis']
      
      # Test best value identification
      best_variant = variants.find { |v| v['is_best_value'] }
      expect(best_variant['name']).to eq('Best Value Pack')
      expect(best_variant['value_rank']).to eq(1)
      
      # Test value analysis calculations
      expect(value_analysis['best_value_display']).to eq('$10.00')
      expect(value_analysis['worst_value_display']).to eq('$25.00')
      expect(value_analysis['max_savings_display']).to eq('$15.00')
      expect(value_analysis['max_savings_percentage']).to eq(60.0) # (25-10)/25 * 100
      expect(value_analysis['variants_with_savings']).to eq(3) # All except best value
      
      # Test individual variant savings
      terrible_deal = variants.find { |v| v['name'] == 'Terrible Deal' }
      expect(terrible_deal['savings_vs_worst']['savings_display']).to eq('$0.00')
      expect(terrible_deal['savings_vs_worst']['savings_percentage']).to eq(0.0)
      
      expensive_single = variants.find { |v| v['name'] == 'Expensive Single' }
      expect(expensive_single['savings_vs_worst']['savings_display']).to eq('$5.00')
      expect(expensive_single['savings_vs_worst']['savings_percentage']).to eq(20.0)
    end
  end

  describe "Enhanced user experience features" do
    let(:product) { create(:product, name: "UX Test Product") }
    let(:completed_job) { create(:extraction_job, :completed, product: product) }

    before do
      create(:product_variant, product: product, name: "Test Variant", 
             price_cents: 1000, quantity_numeric: 1.0, quantity_text: "1 unit")
    end

    it "handles share functionality URL generation" do
      get job_status_path(completed_job.id)
      
      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      
      # The share functionality should use the job ID
      expect(json_response['id']).to eq(completed_job.id)
      
      # Verify the tracking page loads with the job ID (updated for Stimulus format)
      get root_path(job_id: completed_job.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-job-tracker-job-id-value=\"#{completed_job.id}\"")
    end

    it "provides proper filename formatting for exports" do
      get export_results_path(completed_job.id, format: 'csv')
      
      expect(response).to have_http_status(:ok)
      filename = response.headers['Content-Disposition']
      
      # Should include sanitized product name and date
      expect(filename).to include('UX_Test_Product')
      expect(filename).to include(Date.current.strftime('%Y%m%d'))
      expect(filename).to include('.csv')
    end

    it "includes comprehensive table sorting options" do
      get root_path(job_id: completed_job.id)
      
      expect(response).to have_http_status(:ok)
      
      # Test that sorting functionality exists in JavaScript (the table is generated dynamically by Stimulus)
      expect(response.body).to include('function sortTable')
      expect(response.body).to include('value_rank')
      expect(response.body).to include('price_cents')
      expect(response.body).to include('price_cents_desc')
      expect(response.body).to include('name')
    end
  end

  describe "Manual product update flow" do
    let!(:product) { create(:product, name: "Manual Update Product", url: "https://example.com/manual-update") }
    
    before do
      # Create existing variants for the product
      create(:product_variant, product: product, name: "Old Variant 1", 
             price_cents: 5999, quantity_numeric: 1.0, quantity_text: "1 unit")
      create(:product_variant, product: product, name: "Old Variant 2", 
             price_cents: 9999, quantity_numeric: 1.0, quantity_text: "1 unit")
    end

    it "allows manual update of existing products" do
      # Start with 2 existing variants
      expect(product.product_variants.count).to eq(2)
      
      # Mock the WebPageFetcher to return HTML content
      allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
        success: true,
        content: '<html><body>Mock product page content</body></html>',
        url: product.url,
        status_code: 200,
        response_time: 1.5,
        errors: []
      })
      
      # Mock the AI extraction to return new data
      allow_any_instance_of(AiContentExtractor).to receive(:extract_product_data).and_return({
        success: true,
        data: {
          'product' => {
            'name' => 'Updated Manual Product',
            'description' => 'Updated product description'
          },
          'variants' => [
            {
              'name' => 'New Variant 1',
              'price_cents' => 7999,
              'quantity_text' => '1 piece',
              'quantity_numeric' => 1.0,
              'currency' => 'USD'
            },
            {
              'name' => 'New Variant 2', 
              'price_cents' => 14999,
              'quantity_text' => '2 pieces',
              'quantity_numeric' => 2.0,
              'currency' => 'USD'
            },
            {
              'name' => 'New Variant 3',
              'price_cents' => 19999,
              'quantity_text' => '3 pieces',
              'quantity_numeric' => 3.0,
              'currency' => 'USD'
            }
          ]
        },
        raw_response: 'Mocked AI response',
        url: product.url,
        model_used: 'gpt-3.5-turbo',
        response_time: 2.1,
        errors: []
      })
      
      # Trigger manual update
      expect {
        post "/products/#{product.id}/update"
      }.to change(ExtractionJob, :count).by(1)
      
      # Get the created extraction job
      extraction_job = ExtractionJob.last
      expect(extraction_job.url).to eq(product.url)
      expect(extraction_job.status).to eq('queued')
      
      # Process the job
      ProductExtractionJob.new.perform(extraction_job.id)
      
      # Verify the extraction job completed successfully
      extraction_job.reload
      expect(extraction_job.status).to eq('completed')
      expect(extraction_job.error_message).to be_nil
      
      # Verify the product was updated (not duplicated)
      expect(Product.where(url: "https://example.com/manual-update").count).to eq(1)
      
      # Verify old variants were replaced with new ones
      product.reload
      expect(product.name).to eq('Updated Manual Product')
      expect(product.product_variants.count).to eq(3)
      
      # Verify the new variant data
      variant_names = product.product_variants.pluck(:name)
      expect(variant_names).to include('New Variant 1', 'New Variant 2', 'New Variant 3')
      expect(variant_names).not_to include('Old Variant 1', 'Old Variant 2')
      
      # Verify pricing was parsed correctly
      variant_1 = product.product_variants.find_by(name: 'New Variant 1')
      expect(variant_1.price_cents).to eq(7999)
      expect(variant_1.quantity_text).to eq('1 piece')
      expect(variant_1.quantity_numeric).to eq(1.0)
    end

    it "handles manual update errors gracefully" do
      # Mock the WebPageFetcher first 
      allow_any_instance_of(WebPageFetcher).to receive(:fetch).and_return({
        success: true,
        content: '<html><body>Mock product page content</body></html>',
        url: product.url,
        status_code: 200,
        response_time: 1.5,
        errors: []
      })
      
      # Mock the AI extraction to fail
      allow_any_instance_of(AiContentExtractor).to receive(:extract_product_data).and_return({
        success: false,
        data: nil,
        raw_response: nil,
        url: product.url,
        model_used: 'gpt-3.5-turbo',
        response_time: 1.0,
        errors: ['Service unavailable']
      })
      
      # Trigger manual update
      post "/products/#{product.id}/update"
      extraction_job = ExtractionJob.last
      
      # Process the job (which should fail)
      ProductExtractionJob.new.perform(extraction_job.id)
      
      # Verify the job failed appropriately
      extraction_job.reload
      expect(extraction_job.status).to eq('failed')
      expect(extraction_job.error_message).to include('Service unavailable')
      
      # Verify original product data is preserved
      product.reload
      expect(product.product_variants.count).to eq(2)
      expect(product.product_variants.pluck(:name)).to include('Old Variant 1', 'Old Variant 2')
    end

    it "includes manual update button in results display" do
      # Create a completed extraction job with results
      completed_job = create(:extraction_job, :completed, product: product, 
                           result_data: { 'processing_time' => 2.5 })
      
      # Visit the results page
      get "/?job_id=#{completed_job.id}"
      
      # Check that the page includes the job tracker
      expect(response.body).to include('data-controller="job-tracker"')
      expect(response.body).to include('data-job-tracker-job-id-value')
      
      # The manual update button is added via JavaScript in the JobTracker controller
      # We can verify the JavaScript function exists and the job has product data for the button
      expect(response.body).to include('function manualUpdate(productId)')
      expect(response.body).to include("data-job-tracker-job-id-value=\"#{completed_job.id}\"")
      
      # Verify the completed job has associated product data (required for manual update)
      expect(completed_job.product).to be_present
    end
  end
end 
class HomeController < ApplicationController
  def index
    if params[:job_id].present?
      @tracking_job = ExtractionJob.find_by(id: params[:job_id])
    end
    
    # Check for existing product if URL is provided
    if params[:url].present?
      @existing_product = Product.find_by(url: params[:url])
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

    # Check if this URL already has a product
    existing_product = Product.find_by(url: @url)
    
    begin
      # Create extraction job record
      extraction_job = ExtractionJob.create!(
        url: @url,
        status: 'queued',
        progress: 0
      )
      
      # Enqueue background job for processing
      ProductExtractionJob.perform_later(extraction_job.id)
      
      # Set flash message based on whether product exists
      if existing_product
        flash[:info] = "Updating existing product data for this URL. Previous data will be replaced with fresh results."
      else
        flash[:success] = "Product extraction started! Processing your URL now."
      end
      
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

  # New method to check URL and return existing product info
  def check_url
    url = params[:url]
    
    if url.blank? || !valid_url?(url)
      render json: { exists: false, error: "Invalid URL" }
      return
    end
    
    existing_product = Product.includes(:product_variants).find_by(url: url)
    
    if existing_product
      render json: {
        exists: true,
        product: {
          id: existing_product.id,
          name: existing_product.name,
          status: existing_product.status,
          created_at: existing_product.created_at.strftime('%B %d, %Y at %I:%M %p'),
          updated_at: existing_product.updated_at.strftime('%B %d, %Y at %I:%M %p'),
          variants_count: existing_product.product_variants.count,
          last_extraction: existing_product.completed? ? 'Completed' : existing_product.status.humanize
        }
      }
    else
      render json: { exists: false }
    end
  end

  def job_status
    @extraction_job = ExtractionJob.includes(product: :product_variants).find(params[:id])
    
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
        best_value_variant: best_value_info(@extraction_job.product),
        variants: detailed_variants_info(@extraction_job.product),
        price_range: price_range_info(@extraction_job.product),
        value_analysis: value_analysis_info(@extraction_job.product)
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

  def export_results
    @extraction_job = ExtractionJob.includes(product: :product_variants).find(params[:id])
    
    unless @extraction_job.completed? && @extraction_job.product
      redirect_to root_path, alert: 'Results not available for export'
      return
    end
    
    format = params[:format] || 'csv'
    
    case format.downcase
    when 'csv'
      export_csv
    when 'json'
      export_json
    else
      redirect_to root_path, alert: 'Invalid export format'
    end
    
  rescue ActiveRecord::RecordNotFound
    redirect_to root_path, alert: 'Job not found'
  end

  # Manual update trigger for existing products
  def manual_update
    @product = Product.find(params[:id])
    
    begin
      # Create new extraction job for the existing product's URL
      extraction_job = ExtractionJob.create!(
        url: @product.url,
        status: 'queued',
        progress: 0
      )
      
      # Enqueue background job for processing
      ProductExtractionJob.perform_later(extraction_job.id)
      
      # Set flash message indicating manual update
      flash[:info] = "Manual update started for #{@product.name}. Fresh data will replace existing product information."
      
      # Redirect to tracking page
      redirect_to root_path(job_id: extraction_job.id)
      
    rescue ActiveRecord::RecordInvalid => e
      flash[:error] = "Failed to start manual update: #{e.record.errors.full_messages.join(', ')}"
      redirect_back(fallback_location: root_path)
      
    rescue => e
      Rails.logger.error "Error starting manual update for product #{@product.id}: #{e.message}"
      flash[:error] = "An unexpected error occurred while starting the manual update. Please try again."
      redirect_back(fallback_location: root_path)
    end
    
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Product not found"
    redirect_to root_path
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
  
  def detailed_variants_info(product)
    product.product_variants.map do |variant|
      {
        id: variant.id,
        name: variant.name,
        price_cents: variant.price_cents,
        price_display: variant.formatted_price,
        quantity_text: variant.quantity_text || 'N/A',
        quantity_numeric: variant.quantity_numeric,
        price_per_unit_cents: variant.price_per_unit_cents,
        price_per_unit_display: variant.formatted_price_per_unit,
        is_best_value: variant.is_best_value?,
        value_rank: variant.value_rank,
        savings_vs_worst: calculate_savings_vs_worst(variant, product)
      }
    end
  end
  
  def price_range_info(product)
    variants = product.product_variants
    return nil if variants.empty?
    
    prices = variants.map(&:price_cents)
    price_per_units = variants.with_price_per_unit.map(&:price_per_unit_cents)
    
    {
      min_price: prices.min,
      max_price: prices.max,
      min_price_display: format_currency_cents(prices.min),
      max_price_display: format_currency_cents(prices.max),
      min_price_per_unit: price_per_units.min,
      max_price_per_unit: price_per_units.max,
      min_price_per_unit_display: price_per_units.min ? format_currency_cents(price_per_units.min) : 'N/A',
      max_price_per_unit_display: price_per_units.max ? format_currency_cents(price_per_units.max) : 'N/A',
      price_spread: prices.max - prices.min,
      price_spread_display: format_currency_cents(prices.max - prices.min)
    }
  end
  
  def value_analysis_info(product)
    variants_with_value = product.product_variants.with_price_per_unit
    return nil if variants_with_value.empty?
    
    price_per_units = variants_with_value.map(&:price_per_unit_cents)
    best_value = price_per_units.min
    worst_value = price_per_units.max
    
    {
      best_value_cents: best_value,
      worst_value_cents: worst_value,
      best_value_display: format_currency_cents(best_value),
      worst_value_display: format_currency_cents(worst_value),
      max_savings_cents: worst_value - best_value,
      max_savings_display: format_currency_cents(worst_value - best_value),
      max_savings_percentage: worst_value > 0 ? ((worst_value - best_value).to_f / worst_value * 100).round(1) : 0,
      variants_with_savings: variants_with_value.count { |v| v.price_per_unit_cents > best_value }
    }
  end
  
  def calculate_savings_vs_worst(variant, product)
    return nil unless variant.price_per_unit_cents
    
    worst_value = product.product_variants.with_price_per_unit.maximum(:price_per_unit_cents)
    return nil unless worst_value
    
    savings_cents = worst_value - variant.price_per_unit_cents
    savings_percentage = worst_value > 0 ? (savings_cents.to_f / worst_value * 100).round(1) : 0
    
    {
      savings_cents: savings_cents,
      savings_display: format_currency_cents(savings_cents),
      savings_percentage: savings_percentage
    }
  end
  
  def format_currency_cents(cents)
    return '$0.00' if cents.nil? || cents == 0
    dollars = cents / 100.0
    "$#{'%.2f' % dollars}"
  end
  
  def export_csv
    require 'csv'
    
    product = @extraction_job.product
    filename = "#{product.name.gsub(/[^0-9A-Za-z.\-]/, '_')}_variants_#{Date.current.strftime('%Y%m%d')}.csv"
    
    csv_data = CSV.generate(headers: true) do |csv|
      # Header row
      csv << [
        'Variant Name',
        'Price',
        'Quantity',
        'Price Per Unit',
        'Value Rank',
        'Best Value',
        'Savings vs Worst',
        'Savings %'
      ]
      
      # Data rows
      detailed_variants_info(product).each do |variant|
        savings = variant[:savings_vs_worst]
        csv << [
          variant[:name],
          variant[:price_display],
          variant[:quantity_text],
          variant[:price_per_unit_display],
          variant[:value_rank] || 'N/A',
          variant[:is_best_value] ? 'Yes' : 'No',
          savings ? savings[:savings_display] : 'N/A',
          savings ? "#{savings[:savings_percentage]}%" : 'N/A'
        ]
      end
    end
    
    send_data csv_data, filename: filename, type: 'text/csv', disposition: 'attachment'
  end
  
  def export_json
    product = @extraction_job.product
    filename = "#{product.name.gsub(/[^0-9A-Za-z.\-]/, '_')}_data_#{Date.current.strftime('%Y%m%d')}.json"
    
    export_data = {
      extraction_job: {
        id: @extraction_job.id,
        url: @extraction_job.url,
        extracted_at: @extraction_job.updated_at,
        processing_time: @extraction_job.result_data&.dig('processing_time')
      },
      product: {
        name: product.name,
        variants_count: product.product_variants.count,
        variants: detailed_variants_info(product),
        price_range: price_range_info(product),
        value_analysis: value_analysis_info(product)
      }
    }
    
    send_data export_data.to_json, filename: filename, type: 'application/json', disposition: 'attachment'
  end
end

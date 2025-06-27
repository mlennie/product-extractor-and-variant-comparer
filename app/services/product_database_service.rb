class ProductDatabaseService
  def initialize
    # Initialize any required dependencies
  end

  # Save extracted product data to database
  def save_product_data(extracted_data, url)
    return error_result("No extracted data provided") unless extracted_data.present?
    return error_result("URL is required") unless url.present?

    # Validate extracted data structure
    validation_result = validate_extraction_data(extracted_data)
    unless validation_result[:valid]
      return error_result("Invalid data structure: #{validation_result[:errors].join(', ')}")
    end

    start_time = Time.current

    begin
      ActiveRecord::Base.transaction do
        # Create or find product
        product = create_or_update_product(extracted_data, url)
        
        # Clear existing variants to avoid duplicates
        product.product_variants.destroy_all
        
        # Create product variants
        variants = create_product_variants(product, extracted_data['variants'])
        
        # Mark product as completed
        product.mark_as_completed!

        # Find best value variant
        best_variant = product.best_value_variant

        {
          success: true,
          product: product,
          variants: variants,
          best_value_variant: best_variant,
          processing_time: (Time.current - start_time).round(2),
          errors: []
        }
      end

    rescue ActiveRecord::RecordInvalid => e
      error_result("Database validation error: #{e.message}")
    rescue ActiveRecord::RecordNotUnique => e
      error_result("Duplicate record error: #{e.message}")
    rescue => e
      error_result("Database error: #{e.class.name} - #{e.message}")
    end
  end

  # Update product status to processing
  def mark_product_as_processing(url)
    begin
      product = Product.find_or_initialize_by(url: url)
      
      if product.new_record?
        # Set default values for new product
        product.name = extract_domain_from_url(url)
        product.status = 'processing'
        product.save!
      else
        product.mark_as_processing!
      end

      { success: true, product: product, errors: [] }
    rescue => e
      error_result("Error updating product status: #{e.message}")
    end
  end

  # Mark product as failed
  def mark_product_as_failed(url, error_message)
    begin
      product = Product.find_or_initialize_by(url: url)
      
      if product.new_record?
        product.name = extract_domain_from_url(url)
        product.status = 'failed'
        product.save!
      else
        product.mark_as_failed!
      end

      { success: true, product: product, error_message: error_message, errors: [] }
    rescue => e
      error_result("Error marking product as failed: #{e.message}")
    end
  end

  private

  def validate_extraction_data(data)
    errors = []
    
    unless data.is_a?(Hash)
      errors << "Data must be a hash"
      return { valid: false, errors: errors }
    end

    # Validate product section
    unless data['product'].is_a?(Hash)
      errors << "Missing product section"
    else
      errors << "Product name is required" if data['product']['name'].blank?
    end

    # Validate variants section
    unless data['variants'].is_a?(Array)
      errors << "Missing variants section"
    else
      if data['variants'].empty?
        errors << "At least one variant is required"
      else
        data['variants'].each_with_index do |variant, index|
          variant_errors = validate_variant_data(variant, index)
          errors.concat(variant_errors)
        end
      end
    end

    { valid: errors.empty?, errors: errors }
  end

  def validate_variant_data(variant, index)
    errors = []
    prefix = "Variant #{index + 1}:"

    unless variant.is_a?(Hash)
      errors << "#{prefix} Must be a hash"
      return errors
    end

    errors << "#{prefix} Name is required" if variant['name'].blank?
    
    if variant['price_cents'].present?
      unless variant['price_cents'].is_a?(Integer) && variant['price_cents'] >= 0
        errors << "#{prefix} price_cents must be a non-negative integer"
      end
    end

    if variant['quantity_numeric'].present?
      unless variant['quantity_numeric'].is_a?(Numeric) && variant['quantity_numeric'] > 0
        errors << "#{prefix} quantity_numeric must be a positive number"
      end
    end

    errors
  end

  def create_or_update_product(extracted_data, url)
    product_data = extracted_data['product']
    
    product = Product.find_or_initialize_by(url: url)
    
    # Update product attributes
    product.name = product_data['name'].present? ? product_data['name'] : extract_domain_from_url(url)
    product.status = 'processing'
    
    product.save!
    product
  end

  def create_product_variants(product, variants_data)
    return [] unless variants_data.present?

    variants = []
    
    variants_data.each do |variant_data|
      variant = ProductVariant.new(
        product: product,
        name: variant_data['name'],
        quantity_text: variant_data['quantity_text'],
        quantity_numeric: variant_data['quantity_numeric']&.to_f,
        price_cents: variant_data['price_cents']&.to_i || 0,
        currency: variant_data['currency'] || 'USD'
      )
      
      # The before_save callback will automatically calculate price_per_unit_cents
      variant.save!
      variants << variant
    end

    variants
  end

  def extract_domain_from_url(url)
    begin
      uri = URI.parse(url)
      domain = uri.host
      # Clean up common prefixes
      domain = domain.gsub(/^www\./, '') if domain
      domain || "Unknown Product"
    rescue
      "Unknown Product"
    end
  end

  def error_result(message)
    {
      success: false,
      product: nil,
      variants: [],
      best_value_variant: nil,
      processing_time: 0,
      errors: [message]
    }
  end
end 
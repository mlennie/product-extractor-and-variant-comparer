namespace :test do
  desc "Test product extraction pipeline with real URLs"
  task extraction: :environment do
    puts "🚀 Testing AI Product Extraction Pipeline (Step 3)"
    puts "=" * 60

    # Check system health first
    puts "\n📊 System Health Check:"
    extractor = ProductDataExtractor.new
    health = extractor.health_check
    
    puts "Web Fetcher: #{health[:web_fetcher][:available] ? '✅' : '❌'}"
    puts "AI Extractor: #{health[:ai_extractor][:available] ? '✅' : '❌'}"
    puts "Database: #{health[:database_service][:database_connected] ? '✅' : '❌'}"
    puts "OpenAI API Key: #{health[:ai_extractor][:api_key_configured] ? '✅' : '❌'}"
    puts "Overall Status: #{health[:overall_status]}"

    unless health[:overall_status] == 'ready'
      puts "\n❌ System not ready. Please check configuration."
      exit 1
    end

    puts "\n🧪 Testing Pipeline Components:"
    
    # Test pipeline
    pipeline_test = extractor.test_pipeline
    if pipeline_test[:success]
      puts "✅ Pipeline test successful (#{pipeline_test[:processing_time]}s)"
    else
      puts "❌ Pipeline test failed: #{pipeline_test[:errors].join(', ')}"
      exit 1
    end

    # Enhanced test scenarios with real product URLs
    test_scenarios = []
    
    # If user provides a custom URL, use it first
    if ENV['TEST_URL']
      test_scenarios << {
        name: "Custom URL Test",
        url: ENV['TEST_URL'],
        description: "User-provided URL test"
      }
    else
      # Default test scenarios - real e-commerce sites with multiple variants
      test_scenarios = [
        {
          name: "Example.com Test",
          url: "https://example.com",
          description: "Simple, reliable test page for basic functionality"
        },
        {
          name: "HTTPBin HTML Test",
          url: "https://httpbin.org/html",
          description: "Reliable HTML structure test page"
        },
        {
          name: "Scrapethissite Product Test",
          url: "https://scrapethissite.com/pages/",
          description: "Scraping-friendly test site with structured data"
        }
      ]
      
      # Add experimental e-commerce URLs (may not always work)
      experimental_urls = [
        {
          name: "Amazon Echo Dot Test (Experimental)",
          url: "https://www.amazon.com/Amazon-Vibrant-sounding-speaker-bedrooms/dp/B09B93ZDG4",
          description: "Amazon product test (may be blocked)"
        }
      ]
      
      # Only add experimental URLs if user explicitly wants them
      if ENV['INCLUDE_EXPERIMENTAL'] == 'true'
        test_scenarios.concat(experimental_urls)
      end
    end

    # Add a simple fallback test
    test_scenarios << {
      name: "Simple Fallback Test",
      url: "https://httpbin.org/html",
      description: "Basic HTML structure test (fallback)"
    } if test_scenarios.empty?

    test_scenarios.each_with_index do |scenario, index|
      puts "\n" + "=" * 60
      puts "📦 Test #{index + 1}: #{scenario[:name]}"
      puts "🔗 URL: #{scenario[:url]}"
      puts "📝 Description: #{scenario[:description]}"
      puts "-" * 60

      start_time = Time.current
      
      begin
        result = extractor.extract_from_url(scenario[:url])
        end_time = Time.current
        
        puts "\n⏱️  Total Processing Time: #{(end_time - start_time).round(2)}s"
        
        if result[:success]
          puts "✅ Extraction successful!"
          
          # Display product information
          product = result[:product]
          puts "\n📋 Product Information:"
          puts "  Name: #{product.name}"
          puts "  URL: #{product.url}"
          puts "  Status: #{product.status}"
          puts "  ID: #{product.id}"
          
          # Display variants
          variants = result[:variants]
          puts "\n🏷️  Product Variants (#{variants.count}):"
          
          if variants.any?
            variants.each_with_index do |variant, i|
              puts "  #{i + 1}. #{variant.name}"
              puts "     Quantity: #{variant.quantity_display}"
              puts "     Price: #{variant.formatted_price}"
              if variant.price_per_unit_cents
                puts "     Price per unit: #{variant.formatted_price_per_unit}"
                puts "     Value rank: #{variant.value_rank}"
              end
              puts "     Best value: #{variant.is_best_value? ? '🏆' : '📦'}"
              puts
            end
            
            # Show best value
            best_variant = result[:best_value_variant]
            if best_variant
              puts "🏆 Best Value: #{best_variant.name}"
              puts "   Price per unit: #{best_variant.formatted_price_per_unit}"
              puts "   Total price: #{best_variant.formatted_price}"
            end
          else
            puts "   No variants extracted"
          end
          
          # Display processing details
          puts "\n📊 Processing Details:"
          details = result[:details]
          puts "  Web Fetch:"
          puts "    Status: #{details[:fetch_result][:status_code]}"
          puts "    Content Length: #{details[:fetch_result][:content_length]} chars"
          puts "    Response Time: #{details[:fetch_result][:response_time]}s"
          
          puts "  AI Extraction:"
          puts "    Model: #{details[:extraction_result][:model_used]}"
          puts "    Response Time: #{details[:extraction_result][:response_time]}s"
          puts "    Raw Response Length: #{details[:extraction_result][:raw_response_length]} chars"
          
          puts "  Database Save:"
          puts "    Variants Created: #{details[:database_result][:variants_created]}"
          puts "    Processing Time: #{details[:database_result][:processing_time]}s"
          
        else
          puts "❌ Extraction failed!"
          puts "Errors: #{result[:errors].join(', ')}"
          
          # Show details for debugging
          if result[:details]
            puts "\n🔍 Debug Information:"
            puts "Stage: #{result[:details][:stage]}"
            puts "URL: #{result[:details][:url]}"
            
            if result[:details][:fetch_result]
              puts "Fetch Success: #{result[:details][:fetch_result][:success]}"
            end
            
            if result[:details][:extraction_result]
              puts "Extraction Success: #{result[:details][:extraction_result][:success]}"
              if result[:details][:extraction_result][:raw_response]
                puts "Raw AI Response: #{result[:details][:extraction_result][:raw_response][0..200]}..."
              end
            end
          end
        end
        
      rescue => e
        puts "💥 Unexpected error: #{e.class.name} - #{e.message}"
        puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
      end
      
      # Add a small delay between tests to be respectful to servers
      sleep(2) if index < test_scenarios.length - 1
    end

    puts "\n" + "=" * 60
    puts "📈 Summary Statistics:"
    puts "Total Products: #{Product.count}"
    puts "Total Variants: #{ProductVariant.count}"
    puts "Completed Products: #{Product.completed.count}"
    puts "Failed Products: #{Product.failed.count}"
    
    if Product.completed.any?
      puts "\n🏆 Recent Successful Extractions:"
      Product.completed.recent.limit(5).each do |product|
        puts "  • #{product.name} (#{product.variant_count} variants)"
        if product.best_value_variant
          puts "    Best value: #{product.best_value_variant.name} - #{product.best_value_variant.formatted_price_per_unit}"
        end
      end
    end

    puts "\n✨ Test Complete!"
    puts "\n💡 Usage Tips:"
    puts "  • Test with custom URL: TEST_URL='https://example.com' rake test:extraction"
    puts "  • Test single URL only: rake test:extraction_single"
    puts "  • Include experimental e-commerce URLs: INCLUDE_EXPERIMENTAL=true rake test:extraction"
    puts "  • View products in Rails console: Product.completed.recent"
    puts "  • Check variant details: Product.find(ID).product_variants.by_best_value"
    puts "  • See all available test URLs: rake test:show_test_urls"
  end

  desc "Test extraction with a single URL (faster)"
  task extraction_single: :environment do
    puts "🔍 Single URL Product Extraction Test"
    puts "=" * 60

    url = ENV['TEST_URL'] || 'https://www.target.com/p/coca-cola-soda-12pk-12-fl-oz-cans/-/A-13054603'
    puts "Testing URL: #{url}"
    puts "\n" + "-" * 60

    extractor = ProductDataExtractor.new
    
    # Quick health check
    health = extractor.health_check
    unless health[:overall_status] == 'ready'
      puts "❌ System not ready: #{health[:overall_status]}"
      exit 1
    end
    
    start_time = Time.current
    result = extractor.extract_from_url(url)
    
    if result[:success]
      puts "✅ Extraction successful! (#{result[:processing_time]}s)"
      puts "\n📦 Product: #{result[:product].name}"
      puts "🏷️  Variants: #{result[:variants].count}"
      
      if result[:best_value_variant]
        puts "🏆 Best Value: #{result[:best_value_variant].name}"
        puts "   #{result[:best_value_variant].formatted_price_per_unit}"
      end
    else
      puts "❌ Extraction failed: #{result[:errors].join(', ')}"
    end
  end

  desc "Test extraction without saving to database"
  task extraction_dry_run: :environment do
    puts "🔍 Testing AI Product Extraction (Dry Run - No Database Save)"
    puts "=" * 60

    url = ENV['TEST_URL'] || 'https://httpbin.org/html'
    puts "Testing URL: #{url}"

    extractor = ProductDataExtractor.new
    result = extractor.extract_without_saving(url)

    if result[:success]
      puts "✅ Extraction successful!"
      puts "\nExtracted Data:"
      puts JSON.pretty_generate(result[:extracted_data])
    else
      puts "❌ Extraction failed!"
      puts "Errors: #{result[:errors].join(', ')}"
    end

    puts "\n💡 No data was saved to the database (dry run mode)"
  end

  desc "Clean up test data"
  task cleanup_test_data: :environment do
    puts "🧹 Cleaning up test data..."
    
    test_urls = [
      'https://httpbin.org/html',
      'https://example.com',
      'https://www.amazon.com/dp/',
      'https://www.target.com/p/',
      'https://www.bestbuy.com/site/'
    ]
    
    total_removed = 0
    test_urls.each do |url|
      products = Product.where("url LIKE ?", "%#{url}%")
      if products.any?
        count = products.count
        puts "Removing #{count} products matching #{url}"
        products.destroy_all
        total_removed += count
      end
    end
    
    puts "✅ Cleanup complete! Removed #{total_removed} test products."
  end

  desc "Show recommended test URLs for different reliability levels"
  task show_test_urls: :environment do
    puts "🌐 Test URLs for AI Product Extraction by Reliability"
    puts "=" * 60

    puts "\n✅ RELIABLE TEST URLS (Always Work):"
    reliable_urls = [
      {
        name: "Example.com",
        url: "https://example.com",
        description: "Simple page, good for basic AI extraction testing"
      },
      {
        name: "HTTPBin HTML",
        url: "https://httpbin.org/html",
        description: "HTML with structured content, reliable for testing"
      },
      {
        name: "Scrape This Site",
        url: "https://scrapethissite.com/pages/",
        description: "Designed for scraping practice, multiple data formats"
      }
    ]
    
    reliable_urls.each_with_index do |url, index|
      puts "  #{index + 1}. #{url[:name]}"
      puts "     URL: #{url[:url]}"
      puts "     Description: #{url[:description]}"
      puts
    end

    puts "\n⚡ EXPERIMENTAL URLS (May Work):"
    experimental_urls = [
      {
        name: "Amazon Echo Dot",
        url: "https://www.amazon.com/Amazon-Vibrant-sounding-speaker-bedrooms/dp/B09B93ZDG4",
        description: "Current Amazon product page - may be blocked or return complex data"
      },
      {
        name: "Product Hunt",
        url: "https://www.producthunt.com/",
        description: "Product listings - structure may vary"
      }
    ]
    
    experimental_urls.each_with_index do |url, index|
      puts "  #{index + 1}. #{url[:name]}"
      puts "     URL: #{url[:url]}"
      puts "     Description: #{url[:description]}"
      puts
    end

    puts "❌ PROBLEMATIC SITES (Usually Don't Work):"
    puts "  • Most major e-commerce sites (Amazon, Target, Walmart)"
    puts "  • Sites with heavy JavaScript/dynamic content"
    puts "  • Sites with bot protection (Cloudflare, etc.)"
    puts "  • Sites requiring authentication or geo-blocking"

    puts "\n" + "=" * 60
    puts "💡 Usage Examples:"
    puts "  • Test reliable URL:     TEST_URL='https://example.com' rake test:extraction_single"
    puts "  • Test experimental:     TEST_URL='[URL]' rake test:extraction_dry_run"
    puts "  • Full pipeline test:    rake test:extraction"
    puts "  • Include experimental:  INCLUDE_EXPERIMENTAL=true rake test:extraction"
    
    puts "\n🎯 Best Practices:"
    puts "  1. Start with reliable URLs to test your AI prompts"
    puts "  2. Use dry_run mode first for unknown sites"
    puts "  3. For real e-commerce data, consider using APIs instead"
    puts "  4. Add delays between requests to be respectful"
    puts "  5. Check robots.txt before scraping production sites"
    
    puts "\n🔧 For Real Product Testing:"
    puts "  • Create sample HTML files with product structures"
    puts "  • Use local test servers with mock product pages"
    puts "  • Consider using product APIs (Shopify, WooCommerce, etc.)"
    puts "  • Build test fixtures with known product variant patterns"
  end
end 
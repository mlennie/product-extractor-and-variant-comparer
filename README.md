# AI-Powered Product Comparison Tool

A Rails 8 application that extracts and compares product variants from any product page URL using AI. Users can submit product URLs and get real-time analysis of pricing, quantities, and best value recommendations.

https://www.loom.com/share/732a143ddf034df58cbd70d0b41185cf

## 🎯 Overview

This tool helps users compare products across different suppliers or listings based on quantity and pricing. Submit a product page URL, and the system uses OpenAI's AI to extract structured data representing multiple product variants (e.g., "30 tablets", "100 tablets") along with their respective prices, automatically calculating the best value options.

## ✨ Key Features

- **AI-Powered Extraction**: Uses OpenAI API to parse product pages and extract structured variant data
- **Real-time Processing**: Background jobs with live progress updates (25% → 40% → 60% → 85% → 100%)
- **Smart Value Analysis**: Automatically calculates price-per-unit and identifies best value variants
- **Modern UI**: Responsive design with real-time updates using Turbo and Stimulus
- **Export Capabilities**: Download results as CSV or JSON
- **Comprehensive Testing**: 299+ tests with high coverage

## 🔄 URL Update Logic

The application implements intelligent URL handling to ensure **only one product exists per URL** and supports manual updates at any time.

### Core Behavior

When a URL is submitted that already exists in the system:

- ✅ **Updates Existing Product**: Finds the original product record by URL
- ✅ **Replaces All Variants**: Completely removes old variants and creates fresh ones
- ✅ **Preserves Product ID**: Same product record is updated (no duplicates created)
- ✅ **Updates Metadata**: Product name, status, and timestamps are refreshed

### User Experience

- **Real-time Detection**: As users type URLs, the system detects existing products
- **Clear Messaging**: Different notifications for updates vs new extractions:
  - 🔄 "Updating existing product data for this URL. Previous data will be replaced with fresh results."
  - ✅ "Product extraction started! Processing your URL now."
- **Existing Product Info**: Shows current product details when URL already exists
- **Manual Updates**: Users can trigger re-processing of any product at any time

### Technical Implementation

```ruby
# URL Uniqueness Constraint (Database + Model)
validates :url, presence: true, uniqueness: true

# Update Logic in ProductDatabaseService
product = Product.find_or_initialize_by(url: url)  # Find existing or create new
product.product_variants.destroy_all              # Remove old variants
variants = create_product_variants(product, data)  # Create fresh variants
```

### Benefits

- **No Data Bloat**: Prevents duplicate products for the same URL
- **Fresh Information**: Updates always provide current product data
- **User Control**: Manual refresh capability for any product
- **Efficient Storage**: Single source of truth per URL

## 🏗️ Architecture & Design

### Core Components

**Data Models:**
- `Product`: Represents a product extracted from a URL
- `ProductVariant`: Individual variants (size, quantity) with pricing
- `ExtractionJob`: Tracks background processing status

**Services:**
- `WebPageFetcher`: Handles URL fetching with error handling
- `AiContentExtractor`: OpenAI API integration for structured data extraction
- `ProductDataExtractor`: Orchestrates the full extraction pipeline
- `ProductDatabaseService`: Handles database operations and data persistence

**Background Processing:**
- `ProductExtractionJob`: Asynchronous job with progress tracking
- SolidQueue for job processing

**Frontend:**
- Stimulus `JobTrackerController` for real-time updates
- Turbo for seamless page updates
- Progressive status bar with 2-second polling

### Design Principles

1. **Separation of Concerns**: Clear service layer separation
2. **Reliability**: Comprehensive error handling and retry logic
3. **User Experience**: Real-time feedback and progressive status updates
4. **Scalability**: Background processing for time-intensive operations
5. **Testability**: Extensive test coverage with factories and integration tests

### Key Assumptions

- **Product Page Structure**: AI can extract structured data from most e-commerce sites
- **Variant Detection**: Products have multiple size/quantity variants on the same page
- **Price Normalization**: Prices can be converted to comparable units (price-per-unit)
- **Real-time Updates**: Users expect live progress feedback during processing
- **Error Recovery**: Network issues and parsing failures should be handled gracefully

## 🚀 Setup Instructions

### Prerequisites

- **Ruby**: 3.1+ (tested with 3.1.0)
- **Rails**: 8.0+ (using 8.0.2)
- **PostgreSQL**: 14+ (for database)
- **OpenAI API Key**: For AI-powered data extraction

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd product-compare
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Database setup**
   ```bash
   # Ensure PostgreSQL is running
   rails db:create
   rails db:migrate
   rails db:seed
   ```

4. **Environment configuration**
   ```bash
   # Create .env file or set environment variables
   export OPENAI_API_KEY="your-openai-api-key-here"
   ```

5. **Verify setup**
   ```bash
   # Test the extraction pipeline
   rake test:extraction
   ```

## 🏃‍♂️ Running the Application

### Development Server

```bash
# Start the Rails server
rails server

# In a separate terminal, start the job processor
bundle exec jobs
```

The application will be available at `http://localhost:3000`

### Background Jobs

The application uses SolidQueue for background job processing:

```bash
# Start job processing (automatically handles retries)
bundle exec jobs

# Monitor job status
rails console
> ExtractionJob.recent.limit(10)
```

### Usage

1. **Submit a Product URL**
   - Navigate to `http://localhost:3000`
   - Enter a product page URL (e.g., Amazon, Target, etc.)
   - Click "Extract Product Data"

2. **Watch Real-time Progress**
   - Progress bar shows: 25% → 40% → 60% → 85% → 100%
   - Status updates automatically every 2 seconds
   - No page refresh required

3. **View Results**
   - Product variants displayed in sortable table
   - Best value highlighted with 🏆 badge
   - Value analysis showing savings opportunities
   - Export options (CSV, JSON, Share)

## 🧪 Testing

### Test Suite

The application includes comprehensive testing with 299+ tests:

```bash
# Run all tests
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/models/          # Model tests
bundle exec rspec spec/services/        # Service tests
bundle exec rspec spec/jobs/            # Background job tests
bundle exec rspec spec/integration/     # End-to-end tests

# Run tests with documentation format
bundle exec rspec --format documentation
```

### Test Coverage

- **Unit Tests**: Models, services, jobs
- **Integration Tests**: Complete workflow testing
- **Request Tests**: Controller and API endpoints
- **Factory Tests**: Data generation and validation

### Manual Testing

```bash
# Test extraction pipeline
rake test:extraction

# Test individual components
rails console
> extractor = ProductDataExtractor.new
> result = extractor.extract_from_url("https://example.com/product")
```

## 🔧 Configuration

### Environment Variables

```bash
# Required
OPENAI_API_KEY=sk-your-key-here

# Optional
RAILS_ENV=development
DATABASE_URL=postgresql://localhost/product_compare_development
```

### Database Configuration

The application uses PostgreSQL with the following key tables:

- `products`: Core product information
- `product_variants`: Individual variants with pricing
- `extraction_jobs`: Background job tracking
- `solid_queue_*`: Job queue tables

### OpenAI Configuration

The AI extractor is configured in `config/initializers/openai.rb`:

- **Model**: GPT-4 for reliable structured data extraction
- **Temperature**: 0.1 for consistent results
- **Timeout**: 30 seconds for API requests
- **Retry Logic**: 3 attempts with exponential backoff

## 📊 Performance Considerations

### Database Optimization

- Proper indexing on frequently queried fields
- Eager loading to prevent N+1 queries
- Efficient price-per-unit calculations

### N+1 Query Optimization

The application implements efficient eager loading to prevent N+1 query issues, which is critical for performance especially with real-time polling.

#### Problem Identified

**N+1 Query Pattern** occurs when you execute one query to fetch a list of records, then execute additional queries for each record to fetch associated data:

```ruby
# BAD: N+1 Query Pattern (1 + N queries)
@extraction_job = ExtractionJob.find(params[:id])  # 1 query
@extraction_job.product                            # +1 query  
@extraction_job.product.product_variants.count    # +1 query
@extraction_job.product.product_variants.each     # +N queries (one per variant)
```

**Impact**: With 10 product variants, this creates 13+ separate database queries instead of 1 optimized query.

#### Solution Implemented

**Eager Loading with `includes`** loads all associated records in a single optimized query:

```ruby
# GOOD: Eager Loading (1 optimized query)
@extraction_job = ExtractionJob.includes(product: :product_variants).find(params[:id])
@extraction_job.product                            # No additional query
@extraction_job.product.product_variants.count    # No additional query
@extraction_job.product.product_variants.each     # No additional queries
```

#### Specific Changes Made

1. **`HomeController#job_status`** - Fixed real-time polling endpoint:
   ```ruby
   # Before: Multiple queries for each poll
   @extraction_job = ExtractionJob.find(params[:id])
   
   # After: Single optimized query with joins
   @extraction_job = ExtractionJob.includes(product: :product_variants).find(params[:id])
   ```

2. **`HomeController#export_results`** - Fixed export functionality:
   ```ruby
   # Before: Multiple queries for CSV/JSON export
   @extraction_job = ExtractionJob.find(params[:id])
   
   # After: Single query with eager loading
   @extraction_job = ExtractionJob.includes(product: :product_variants).find(params[:id])
   ```

#### Performance Benefits

- **Query Reduction**: From 5-15+ queries down to 1 optimized query
- **Real-time Polling**: Critical for 2-second polling intervals in the UI
- **Scalability**: Performance scales linearly with more variants instead of exponentially
- **Database Load**: Reduces connection overhead and improves concurrent user handling

#### Verification

All 299 tests continue to pass, confirming that the optimization maintains identical functionality while improving performance:

```bash
bundle exec rspec --format progress
# 299 examples, 0 failures
```

The eager loading changes are **transparent** to application behavior - same data returned, just more efficiently.

### Background Processing

- SolidQueue for reliable job processing
- Progressive status updates for user feedback
- Retry logic for failed extractions

### Caching Strategy

- CSS/JS asset compilation and caching
- Database query optimization
- Turbo caching for improved navigation

## 🚨 Error Handling

### User-Friendly Error Messages

- Network issues: "Unable to fetch the webpage"
- AI parsing failures: "Could not extract product data"
- Invalid URLs: Clear validation messages

### Technical Error Recovery

- Automatic retries for transient failures
- Detailed logging for debugging
- Graceful degradation for partial data

### Monitoring

```bash
# Check recent jobs
rails console
> ExtractionJob.failed.recent

# View error logs
tail -f log/development.log
```

## 🛠️ Development Notes

### Code Organization

```
app/
├── controllers/     # Web controllers
├── jobs/           # Background jobs
├── models/         # ActiveRecord models
├── services/       # Business logic services
├── views/          # ERB templates
└── javascript/     # Stimulus controllers

spec/
├── factories/      # Test data factories
├── integration/    # End-to-end tests
├── models/         # Model unit tests
├── services/       # Service unit tests
└── jobs/          # Job tests
```

### Key Technologies

- **Rails 8.0.2**: Latest Rails with modern defaults
- **Turbo + Stimulus**: Hotwired for real-time updates
- **SolidQueue**: Reliable background job processing
- **RSpec + FactoryBot**: Comprehensive testing framework
- **PostgreSQL**: Robust relational database
- **OpenAI API**: AI-powered data extraction

### Future Enhancements

- Product management dashboard
- Bulk URL processing
- Price history tracking
- Email notifications for price changes
- API endpoints for external integrations

## 📝 License

This project is developed as an assessment project and is not intended for commercial use.

---

**Assessment Time**: ~4-5 hours total development time
**Test Coverage**: 299+ tests with comprehensive coverage
**Status**: Production-ready with full error handling and user experience features

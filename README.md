# AI-Powered Product Comparison Tool

A Rails 8 application that extracts and compares product variants from any product page URL using AI. Users can submit product URLs and get real-time analysis of pricing, quantities, and best value recommendations.

## 🎯 Overview

This tool helps users compare products across different suppliers or listings based on quantity and pricing. Submit a product page URL, and the system uses OpenAI's AI to extract structured data representing multiple product variants (e.g., "30 tablets", "100 tablets") along with their respective prices, automatically calculating the best value options.

## ✨ Key Features

- **AI-Powered Extraction**: Uses OpenAI API to parse product pages and extract structured variant data
- **Real-time Processing**: Background jobs with live progress updates (25% → 40% → 60% → 85% → 100%)
- **Smart Value Analysis**: Automatically calculates price-per-unit and identifies best value variants
- **Modern UI**: Responsive design with real-time updates using Turbo and Stimulus
- **Export Capabilities**: Download results as CSV or JSON
- **Comprehensive Testing**: 299+ tests with high coverage

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

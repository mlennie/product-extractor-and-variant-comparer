import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["progressFill", "progressText", "statusBadge", "statusIcon", "statusText", "results", "error", "header"]
  static values = { 
    jobId: String,
    pollInterval: { type: Number, default: 2000 }
  }

  connect() {
    console.log("JobTracker controller connected for job:", this.jobIdValue)
    
    if (!this.jobIdValue) {
      console.error("No job ID provided!")
      return
    }

    // Status icons mapping
    this.statusIcons = {
      'queued': '⏳',
      'processing': '🔄',
      'completed': '✅',
      'failed': '❌'
    }

    this.startPolling()
  }

  disconnect() {
    console.log("JobTracker controller disconnected")
    this.stopPolling()
  }

  startPolling() {
    console.log("Starting polling for job:", this.jobIdValue)
    
    // Poll immediately, then set interval
    this.pollJobStatus()
    this.pollTimer = setInterval(() => {
      this.pollJobStatus()
    }, this.pollIntervalValue)
  }

  stopPolling() {
    if (this.pollTimer) {
      console.log("Stopping polling")
      clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }

  async pollJobStatus() {
    try {
      console.log("Polling job status for job ID:", this.jobIdValue)
      
      const response = await fetch(`/jobs/${this.jobIdValue}/status`)
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }
      
      const data = await response.json()
      console.log("Received job data:", data)
      
      if (data.error) {
        console.error("Job not found:", data.error)
        this.stopPolling()
        return
      }
      
      this.updateJobStatus(data)
      
    } catch (error) {
      console.error("Error polling job status:", error)
      // Continue polling on error
    }
  }

  updateJobStatus(data) {
    console.log("Updating job status:", data.status, "Progress:", data.progress)
    
    // Update progress bar
    if (this.hasProgressFillTarget && this.hasProgressTextTarget) {
      this.progressFillTarget.style.width = data.progress + '%'
      this.progressTextTarget.textContent = data.progress_display
    }

    // Update status badge
    if (this.hasStatusBadgeTarget && this.hasStatusIconTarget && this.hasStatusTextTarget) {
      this.statusBadgeTarget.setAttribute('data-status', data.status)
      this.statusIconTarget.textContent = this.statusIcons[data.status] || '⏳'
      this.statusTextTarget.textContent = data.status_display
    }

    // Handle completion
    if (data.status === 'completed' && data.product) {
      this.showJobResults(data)
      this.stopPolling()
      this.updateHeader('✅ Extraction Complete!')
    }

    // Handle failure
    if (data.status === 'failed' && data.error_message) {
      this.showJobError(data)
      this.stopPolling()
      this.updateHeader('❌ Extraction Failed')
    }
  }

  updateHeader(text) {
    if (this.hasHeaderTarget) {
      this.headerTarget.textContent = text
    }
  }

  showJobResults(data) {
    if (!this.hasResultsTarget) return

    console.log("Showing job results")
    
    // Hide error container
    if (this.hasErrorTarget) {
      this.errorTarget.style.display = 'none'
    }

    let resultsHTML = this.buildResultsHTML(data)
    
    this.resultsTarget.innerHTML = resultsHTML
    this.resultsTarget.style.display = 'block'
    
    // Store variants data globally for sorting
    window.variantsData = data.product.variants
  }

  showJobError(data) {
    if (!this.hasErrorTarget) return

    console.log("Showing job error:", data.error_message)
    
    // Hide results container
    if (this.hasResultsTarget) {
      this.resultsTarget.style.display = 'none'
    }

    let errorHTML = this.buildErrorHTML(data)
    
    this.errorTarget.innerHTML = errorHTML
    this.errorTarget.style.display = 'block'
  }

  buildResultsHTML(data) {
    let html = '<div class="results-header">'
    html += '<h3>🎉 Product Data Successfully Extracted!</h3>'
    html += '<div class="results-summary">'
    html += `<div class="summary-item"><strong>Product:</strong> ${data.product.name}</div>`
    html += `<div class="summary-item"><strong>Variants Found:</strong> ${data.product.variants_count}</div>`
    
    if (data.processing_time) {
      html += `<div class="summary-item"><strong>Processing Time:</strong> ${data.processing_time}s</div>`
    }
    html += '</div>'
    
    // Export buttons
    html += '<div class="export-actions">'
    html += `<button onclick="exportResults('${data.id}', 'csv')" class="export-btn csv-btn">📊 Export CSV</button>`
    html += `<button onclick="exportResults('${data.id}', 'json')" class="export-btn json-btn">📄 Export JSON</button>`
    html += `<button onclick="shareResults('${data.id}')" class="export-btn share-btn">🔗 Share Results</button>`
    html += `<button onclick="manualUpdate('${data.product.id}')" class="export-btn update-btn">🔄 Update Product Data</button>`
    html += '</div>'
    html += '</div>'
    
    // Value Analysis
    if (data.product.value_analysis) {
      html += this.buildValueAnalysisHTML(data.product.value_analysis)
    }
    
    // Variants Table
    if (data.product.variants && data.product.variants.length > 0) {
      html += this.buildVariantsTableHTML(data.product.variants)
    }
    
    return html
  }

  buildValueAnalysisHTML(analysis) {
    return `
      <div class="value-analysis">
        <h4>💰 Value Analysis</h4>
        <div class="analysis-grid">
          <div class="analysis-item best"><strong>Best Value:</strong> ${analysis.best_value_display}</div>
          <div class="analysis-item worst"><strong>Worst Value:</strong> ${analysis.worst_value_display}</div>
          <div class="analysis-item savings"><strong>Max Savings:</strong> ${analysis.max_savings_display} (${analysis.max_savings_percentage}%)</div>
          <div class="analysis-item count"><strong>Variants with Savings:</strong> ${analysis.variants_with_savings}</div>
        </div>
      </div>
    `
  }

  buildVariantsTableHTML(variants) {
    let html = `
      <div class="variants-section">
        <div class="variants-header">
          <h4>📋 Product Variants</h4>
          <div class="table-controls">
            <label>Sort by: 
              <select id="sort-select" onchange="sortTable(this.value)">
                <option value="value_rank">Value Rank</option>
                <option value="price_cents">Price (Low to High)</option>
                <option value="price_cents_desc">Price (High to Low)</option>
                <option value="name">Name</option>
              </select>
            </label>
          </div>
        </div>
        <div class="table-container">
          <table class="variants-table" id="variants-table">
            <thead>
              <tr>
                <th>Variant</th><th>Price</th><th>Quantity</th>
                <th>Price/Unit</th><th>Rank</th><th>Savings</th>
              </tr>
            </thead>
            <tbody id="variants-tbody">
    `
    
    html += this.generateVariantRows(variants)
    html += '</tbody></table></div></div>'
    
    return html
  }

  generateVariantRows(variants) {
    return variants.map(variant => {
      const bestValueClass = variant.is_best_value ? 'best-value' : ''
      const savings = variant.savings_vs_worst
      const savingsDisplay = savings ? `${savings.savings_display} (${savings.savings_percentage}%)` : 'N/A'
      const rankDisplay = variant.value_rank || 'N/A'
      
      return `
        <tr class="${bestValueClass}" data-variant-id="${variant.id}">
          <td class="variant-name">
            <strong>${variant.name}</strong>
            ${variant.is_best_value ? '<span class="best-badge">🏆 Best Value</span>' : ''}
          </td>
          <td class="price">${variant.price_display}</td>
          <td class="quantity">${variant.quantity_text}</td>
          <td class="price-per-unit">${variant.price_per_unit_display}</td>
          <td class="rank">${rankDisplay}</td>
          <td class="savings">${savingsDisplay}</td>
        </tr>
      `
    }).join('')
  }

  buildErrorHTML(data) {
    let html = '<h3>❌ Extraction Failed</h3>'
    html += '<p>We encountered an error while processing your request:</p>'
    
    const userFriendlyMessage = this.getUserFriendlyErrorMessage(data.error_message)
    html += `<div class="error-message">${userFriendlyMessage}</div>`
    
    if (data.error_message) {
      html += '<details class="technical-details">'
      html += '<summary>Technical Details</summary>'
      html += `<div class="error-details">${data.error_message}</div>`
      html += '</details>'
    }
    
    html += '<div class="error-actions">'
    html += '<button onclick="retryExtraction()" class="btn btn-retry">🔄 Try Again</button>'
    html += `<button onclick="reportIssue('${data.id}')" class="btn btn-secondary">📋 Report Issue</button>`
    html += '</div>'
    
    return html
  }

  getUserFriendlyErrorMessage(technicalError) {
    if (!technicalError) return 'An unknown error occurred.'
    
    const errorLower = technicalError.toLowerCase()
    
    if (errorLower.includes('403') || errorLower.includes('forbidden')) {
      return '🚫 <strong>Access Blocked:</strong> The website is blocking automated requests. This is common for sites with anti-bot protection. Try a different product URL from a site like Target, Walmart, or a smaller retailer.'
    } else if (errorLower.includes('404') || errorLower.includes('not found')) {
      return '🔍 <strong>Page Not Found:</strong> The product page could not be found. Please check that the URL is correct and the product still exists.'
    } else if (errorLower.includes('timeout') || errorLower.includes('timed out')) {
      return '⏱️ <strong>Request Timeout:</strong> The website took too long to respond. This might be a temporary issue - please try again.'
    } else if (errorLower.includes('connection') || errorLower.includes('network')) {
      return '🌐 <strong>Connection Error:</strong> Unable to connect to the website. Please check the URL and try again.'
    } else if (errorLower.includes('rate limit') || errorLower.includes('too many requests')) {
      return '🚦 <strong>Rate Limited:</strong> Too many requests have been made. Please wait a few minutes before trying again.'
    } else if (errorLower.includes('ssl') || errorLower.includes('certificate')) {
      return '🔒 <strong>Security Error:</strong> There\'s an issue with the website\'s security certificate. Try a different URL.'
    } else if (errorLower.includes('parsing') || errorLower.includes('extract')) {
      return '📄 <strong>Content Error:</strong> Unable to extract product information from this page. The page might not contain product data or might be in an unsupported format.'
    } else {
      return '❗ <strong>Processing Error:</strong> Something went wrong while extracting the product data. Please try again or contact support if the issue persists.'
    }
  }
} 
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["urlInput", "existingInfo", "existingContent", "submitButton"]
  
  connect() {
    this.checkTimeout = null
    this.lastCheckedUrl = null
  }
  
  disconnect() {
    if (this.checkTimeout) {
      clearTimeout(this.checkTimeout)
    }
  }
  
  checkUrl() {
    const url = this.urlInputTarget.value.trim()
    
    // Don't check if URL is empty or same as last checked
    if (!url || url === this.lastCheckedUrl) {
      return
    }
    
    // Clear previous timeout
    if (this.checkTimeout) {
      clearTimeout(this.checkTimeout)
    }
    
    // Hide existing info while checking
    this.hideExistingInfo()
    
    // Debounce the check - wait 500ms after user stops typing
    this.checkTimeout = setTimeout(() => {
      this.performUrlCheck(url)
    }, 500)
  }
  
  async performUrlCheck(url) {
    // Basic URL validation
    if (!this.isValidUrl(url)) {
      this.hideExistingInfo()
      return
    }
    
    this.lastCheckedUrl = url
    
    try {
      const response = await fetch('/check_url', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content
        },
        body: JSON.stringify({ url: url })
      })
      
      const data = await response.json()
      
      if (data.exists) {
        this.showExistingProduct(data.product)
        this.updateSubmitButton(true)
      } else {
        this.hideExistingInfo()
        this.updateSubmitButton(false)
      }
      
    } catch (error) {
      console.error('Error checking URL:', error)
      this.hideExistingInfo()
    }
  }
  
  showExistingProduct(product) {
    const content = `
      <div class="info-row">
        <span class="info-label">Product Name:</span>
        <span class="info-value">${product.name}</span>
      </div>
      <div class="info-row">
        <span class="info-label">Status:</span>
        <span class="info-value">${product.last_extraction}</span>
      </div>
      <div class="info-row">
        <span class="info-label">Variants Found:</span>
        <span class="info-value">${product.variants_count} variants</span>
      </div>
      <div class="info-row">
        <span class="info-label">First Extracted:</span>
        <span class="info-value">${product.created_at}</span>
      </div>
      <div class="info-row">
        <span class="info-label">Last Updated:</span>
        <span class="info-value">${product.updated_at}</span>
      </div>
    `
    
    this.existingContentTarget.innerHTML = content
    this.existingInfoTarget.style.display = 'block'
  }
  
  hideExistingInfo() {
    this.existingInfoTarget.style.display = 'none'
  }
  
  updateSubmitButton(isUpdate) {
    if (isUpdate) {
      this.submitButtonTarget.value = "🔄 Update Product Data"
      this.submitButtonTarget.classList.add('btn-update')
    } else {
      this.submitButtonTarget.value = "Extract Product Data"
      this.submitButtonTarget.classList.remove('btn-update')
    }
  }
  
  isValidUrl(url) {
    try {
      const urlObj = new URL(url)
      return urlObj.protocol === 'http:' || urlObj.protocol === 'https:'
    } catch {
      return false
    }
  }
} 
class ExtractionJob < ApplicationRecord
  belongs_to :product, optional: true

  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
  validates :status, presence: true, inclusion: { in: %w[queued processing completed failed] }
  validates :progress, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 100 }

  scope :queued, -> { where(status: 'queued') }
  scope :processing, -> { where(status: 'processing') }
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :recent, -> { order(created_at: :desc) }

  def queued?
    status == 'queued'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end

  def finished?
    completed? || failed?
  end

  def in_progress?
    queued? || processing?
  end

  def mark_as_processing!
    update!(status: 'processing', progress: 0)
  end

  def mark_as_completed!(product, result_data = nil)
    update!(
      status: 'completed',
      progress: 100,
      product: product,
      result_data: result_data,
      error_message: nil
    )
  end

  def mark_as_failed!(error_message)
    update!(
      status: 'failed',
      progress: 0,
      error_message: error_message,
      result_data: nil
    )
  end

  def update_progress!(progress_percent, message = nil)
    update!(
      progress: progress_percent.clamp(0, 100),
      error_message: message
    )
  end

  def status_display
    case status
    when 'queued'
      'Queued for processing'
    when 'processing'
      'Extracting product data'
    when 'completed'
      'Extraction completed'
    when 'failed'
      'Extraction failed'
    else
      status.humanize
    end
  end

  def progress_display
    "#{progress}%"
  end
end 
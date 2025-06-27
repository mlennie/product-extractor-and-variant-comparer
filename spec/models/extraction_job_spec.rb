require 'rails_helper'

RSpec.describe ExtractionJob, type: :model do
  let(:valid_url) { 'https://example.com' }
  let(:invalid_url) { 'not-a-url' }

  describe 'validations' do
    it 'requires a URL' do
      job = ExtractionJob.new(status: 'queued', progress: 0)
      expect(job).not_to be_valid
      expect(job.errors[:url]).to include("can't be blank")
    end

    it 'validates URL format' do
      job = ExtractionJob.new(url: invalid_url)
      expect(job).not_to be_valid
      expect(job.errors[:url]).to include('is invalid')
    end

    it 'validates status inclusion' do
      job = ExtractionJob.new(url: valid_url, status: 'invalid_status')
      expect(job).not_to be_valid
      expect(job.errors[:status]).to include('is not included in the list')
    end

    it 'validates progress range' do
      job = ExtractionJob.new(url: valid_url, progress: -1)
      expect(job).not_to be_valid
      expect(job.errors[:progress]).to include('must be greater than or equal to 0')

      job.progress = 101
      expect(job).not_to be_valid
      expect(job.errors[:progress]).to include('must be less than or equal to 100')
    end
  end

  describe 'associations' do
    it 'belongs to product optionally' do
      job = ExtractionJob.create!(url: valid_url)
      expect(job.product).to be_nil
      expect(job).to be_valid
    end
  end

  describe 'default values' do
    it 'sets default status to queued' do
      job = ExtractionJob.new(url: valid_url)
      expect(job.status).to eq('queued')
    end

    it 'sets default progress to 0' do
      job = ExtractionJob.new(url: valid_url)
      expect(job.progress).to eq(0)
    end
  end

  describe 'scopes' do
    let!(:queued_job) { ExtractionJob.create!(url: valid_url, status: 'queued') }
    let!(:processing_job) { ExtractionJob.create!(url: valid_url, status: 'processing') }
    let!(:completed_job) { ExtractionJob.create!(url: valid_url, status: 'completed') }
    let!(:failed_job) { ExtractionJob.create!(url: valid_url, status: 'failed') }

    it 'filters by status' do
      expect(ExtractionJob.queued).to contain_exactly(queued_job)
      expect(ExtractionJob.processing).to contain_exactly(processing_job)
      expect(ExtractionJob.completed).to contain_exactly(completed_job)
      expect(ExtractionJob.failed).to contain_exactly(failed_job)
    end

    it 'orders by created_at desc' do
      expect(ExtractionJob.recent.first).to eq(failed_job) # Most recent
      expect(ExtractionJob.recent.last).to eq(queued_job) # Oldest
    end
  end

  describe 'status check methods' do
    let(:job) { ExtractionJob.create!(url: valid_url) }

    it 'checks if queued' do
      expect(job.queued?).to be true
      expect(job.processing?).to be false
      expect(job.completed?).to be false
      expect(job.failed?).to be false
    end

    it 'checks if finished' do
      expect(job.finished?).to be false
      expect(job.in_progress?).to be true

      job.update!(status: 'completed')
      expect(job.finished?).to be true
      expect(job.in_progress?).to be false
    end
  end

  describe 'status update methods' do
    let(:job) { ExtractionJob.create!(url: valid_url) }

    describe '#mark_as_processing!' do
      it 'updates status and resets progress' do
        job.update!(progress: 50)
        job.mark_as_processing!
        
        expect(job.status).to eq('processing')
        expect(job.progress).to eq(0)
      end
    end

    describe '#mark_as_completed!' do
      let(:product) { create(:product) }

      it 'updates status, progress and associates product' do
        job.mark_as_completed!(product, { test: 'data' })
        
        expect(job.status).to eq('completed')
        expect(job.progress).to eq(100)
        expect(job.product).to eq(product)
        expect(job.result_data).to eq({ 'test' => 'data' })
        expect(job.error_message).to be_nil
      end
    end

    describe '#mark_as_failed!' do
      it 'updates status and sets error message' do
        job.mark_as_failed!('Test error message')
        
        expect(job.status).to eq('failed')
        expect(job.progress).to eq(0)
        expect(job.error_message).to eq('Test error message')
        expect(job.result_data).to be_nil
      end
    end

    describe '#update_progress!' do
      it 'updates progress within valid range' do
        job.update_progress!(75, 'Processing...')
        
        expect(job.progress).to eq(75)
        expect(job.error_message).to eq('Processing...')
      end

      it 'clamps progress to valid range' do
        job.update_progress!(-10)
        expect(job.progress).to eq(0)

        job.update_progress!(150)
        expect(job.progress).to eq(100)
      end
    end
  end

  describe 'display methods' do
    let(:job) { ExtractionJob.create!(url: valid_url) }

    it 'returns status display' do
      expect(job.status_display).to eq('Queued for processing')
      
      job.update!(status: 'processing')
      expect(job.status_display).to eq('Extracting product data')
      
      job.update!(status: 'completed')
      expect(job.status_display).to eq('Extraction completed')
      
      job.update!(status: 'failed')
      expect(job.status_display).to eq('Extraction failed')
    end

    it 'returns progress display' do
      expect(job.progress_display).to eq('0%')
      
      job.update!(progress: 75)
      expect(job.progress_display).to eq('75%')
    end
  end
end 
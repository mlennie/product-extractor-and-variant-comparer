FactoryBot.define do
  factory :extraction_job do
    url { 'https://example.com' }
    status { 'queued' }
    progress { 0 }
    
    trait :processing do
      status { 'processing' }
      progress { 50 }
    end
    
    trait :completed do
      status { 'completed' }
      progress { 100 }
      association :product
      result_data { { test: 'data' } }
    end
    
    trait :failed do
      status { 'failed' }
      progress { 0 }
      error_message { 'Test error message' }
    end
  end
end 
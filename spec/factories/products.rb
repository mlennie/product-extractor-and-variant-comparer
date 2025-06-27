FactoryBot.define do
  factory :product do
    name { "Sample Product" }
    url { "https://example.com/product/#{SecureRandom.hex(4)}" }
    status { "pending" }

    trait :pending do
      status { "pending" }
    end

    trait :processing do
      status { "processing" }
    end

    trait :completed do
      status { "completed" }
    end

    trait :failed do
      status { "failed" }
    end

    trait :with_variants do
      after(:create) do |product|
        create_list(:product_variant, 3, product: product)
      end
    end

    trait :with_best_value_variant do
      after(:create) do |product|
        create(:product_variant, product: product, quantity_numeric: 100, price_cents: 2000) # $0.20 per unit
        create(:product_variant, product: product, quantity_numeric: 50, price_cents: 1500)  # $0.30 per unit
        create(:product_variant, product: product, quantity_numeric: 30, price_cents: 1200)  # $0.40 per unit
      end
    end
  end
end

FactoryBot.define do
  factory :product_variant do
    association :product
    name { "Sample Variant #{rand(1..100)}" }
    quantity_text { nil }
    quantity_numeric { rand(10..100) }
    price_cents { rand(500..5000) } # $5.00 to $50.00
    currency { "USD" }

    # price_per_unit_cents will be calculated automatically via callback

    trait :with_quantity do
      quantity_numeric { 30 }
      quantity_text { "30 tablets" }
    end

    trait :expensive do
      price_cents { 10000 } # $100.00
    end

    trait :cheap do
      price_cents { 500 } # $5.00
    end

    trait :large_quantity do
      quantity_numeric { 100 }
      quantity_text { "100 tablets" }
    end

    trait :small_quantity do
      quantity_numeric { 10 }
      quantity_text { "10 tablets" }
    end

    trait :best_value do
      quantity_numeric { 100 }
      price_cents { 1000 } # $10.00 for 100 = $0.10 per unit
      quantity_text { "100 tablets - Best Value!" }
    end

    trait :without_quantity do
      quantity_numeric { nil }
      quantity_text { nil }
    end

    trait :euro_currency do
      currency { "EUR" }
    end
  end
end

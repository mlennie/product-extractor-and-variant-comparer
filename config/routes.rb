Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Home routes
  get "home/index"
  root "home#index"
  
  # Product extraction routes
  post "extract", to: "home#create"
  post "check_url", to: "home#check_url"
  post "products/:id/update", to: "home#manual_update", as: :manual_update_product
  get "jobs/:id/status", to: "home#job_status", as: :job_status
  get "jobs/:id/export", to: "home#export_results", as: :export_results
end

Pod::Spec.new do |s|
  s.name             = "KlaviyoForms"
  s.version          = "0.1.0"
  s.summary          = "UI components for the Klaviyo"
  s.description      = <<-DESC
                        UI components and utilities for the Klaviyo SDK.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoForms/**/*.swift'
  s.resource_bundles = {
    'KlaviyoFormsResources' => [
      'Sources/KlaviyoForms/InAppForms/Assets/*.{html}',
      'Tests/KlaviyoFormsTests/Assets/*.{html}'
    ]
  }
  # update once modularization changes are merged in.
  s.dependency     'KlaviyoSwift', '~> 4.0.0'
end

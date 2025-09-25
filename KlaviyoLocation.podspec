Pod::Spec.new do |s|
  s.name             = "KlaviyoLocation"
  s.version          = "0.1.0"
  s.summary          = "Location services and geofencing for the Klaviyo SDK"
  s.description      = <<-DESC
                        Use KlaviyoLocation to enable location-based tracking and geofencing capabilities in your iOS applications.
                        This module provides geofence management, location tracking, and location-based event triggers.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoLocation/**/*.swift'
  s.resource_bundles = {
    'KlaviyoLocationResources' => [
      'Sources/KlaviyoLocation/Assets/*.{json}'
    ]
  }
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoLocation' }
  s.dependency       'KlaviyoSwift'
  s.frameworks       = 'CoreLocation'
end

Pod::Spec.new do |s|
  s.name             = "KlaviyoCore"
  s.version          = "5.2.0-alpha.1"
  s.summary          = "Core functionalities for the Klaviyo SDK"
  s.description      = <<-DESC
                        Core functionalities and utilities for the Klaviyo SDK.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoCore/**/*.swift'
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoCore' }
  s.dependency       'AnyCodable-FlightSchool'
end

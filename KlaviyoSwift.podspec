Pod::Spec.new do |s|
  s.name             = "KlaviyoSwift"
  s.version          = "5.0.1"
  s.summary          = "Incorporate Klaviyo's event and person tracking and push notifications functionality into iOS applications"

  s.description      = <<-DESC
                        Use the Klaviyo SDK to incorporate Klaviyo's event and person tracking functionality and push notifications within iOS applications. Written in Swift.'
                       DESC

  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version = '5.7'
  s.platform = :ios
  s.ios.deployment_target = '13.0'
  s.source_files = 'Sources/KlaviyoSwift/**/*.swift'
  s.resource_bundles = {"KlaviyoSwift" => ["Sources/KlaviyoSwift/PrivacyInfo.xcprivacy"]}
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoSwift -package-name KlaviyoCore' }
  s.dependency     'KlaviyoCore', '~> 5.0.1'
  s.dependency     'AnyCodable-FlightSchool'
end

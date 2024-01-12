Pod::Spec.new do |s|
  s.name             = "KlaviyoSwiftExtension"
  s.version          = "3.0.0"
  s.summary          = "Incorporate Klaviyo's rich push notifications functionality into your iOS applications"

  s.description      = <<-DESC
                          Incorporate Klaviyo's rich push notifications functionality into your iOS applications. Written in Swift.'
                       DESC

  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version = '5.7'
  s.platform = :ios
  s.ios.deployment_target = '14.0'
  s.source_files = 'Sources/KlaviyoSwiftExtension/**/*.swift'
end

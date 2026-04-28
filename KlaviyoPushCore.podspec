Pod::Spec.new do |s|
  s.name             = "KlaviyoPushCore"
  s.version          = "5.3.0"
  s.summary          = "Extension-safe push notification primitives for the Klaviyo SDK"
  s.description      = <<-DESC
                        Extension-safe shared types for push notification handling in the Klaviyo SDK.
                        Safe to use in both main app targets and Notification Service Extension targets.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoPushCore/**/*.swift'
end

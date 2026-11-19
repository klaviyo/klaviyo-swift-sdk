Pod::Spec.new do |s|
  s.name             = "KlaviyoFoundation"
  s.version          = "5.4.1"
  s.summary          = "Shared enums and constants for the Klaviyo SDK, safe for app extensions"
  s.description      = <<-DESC
                        Enums and constants shared by the app-facing and extension-facing Klaviyo SDK modules.
                        Depends only on Foundation.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoFoundation/**/*.swift'
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoCore' }
end

Pod::Spec.new do |s|
  s.name             = "KlaviyoInbox"
  s.version          = "5.4.1"
  s.summary          = "Klaviyo Mobile Inbox for your app"
  s.description      = <<-DESC
                        Register your app for Klaviyo Mobile Inbox. Link this in your app target; link
                        KlaviyoInboxExtension in your Notification Service Extension.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoInbox/**/*.swift'
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoCore' }
  s.dependency       'KlaviyoCore', '~> 5.4.1'
  s.dependency       'KlaviyoInboxCore', '~> 5.4.1'
end

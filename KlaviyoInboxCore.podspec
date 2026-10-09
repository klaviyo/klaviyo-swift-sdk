Pod::Spec.new do |s|
  s.name             = "KlaviyoInboxCore"
  s.version          = "5.4.1"
  s.summary          = "Shared internals for Klaviyo Mobile Inbox, safe for app extensions"
  s.description      = <<-DESC
                        Shared configuration and storage plumbing used by both the app-facing KlaviyoInbox
                        and the extension-facing KlaviyoInboxExtension. Depends only on Foundation.
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '13.0'
  s.source_files     = 'Sources/KlaviyoInboxCore/**/*.swift'
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoCore' }
end

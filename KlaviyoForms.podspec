Pod::Spec.new do |s|
  s.name             = "KlaviyoForms"
  s.version          = "5.1.1"
  s.summary          = "Klaviyo forms is a new way to engage with your app users"
  s.description      = <<-DESC
                        Use Klaviyo forms to include in app forms in your app and engage user with marketing content
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
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '-package-name KlaviyoSwift -package-name KlaviyoCore' }
  s.dependency     'KlaviyoSwift', '~> 5.1.1'
end

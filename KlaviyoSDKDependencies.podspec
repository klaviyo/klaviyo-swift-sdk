Pod::Spec.new do |s|
  s.name             = "KlaviyoSDKDependencies"
  s.version          = "4.0.0"
  s.summary          = "Dependency for the Klaviyo SDK"
  s.description      = <<-DESC
                        Klaviyo external dependencies all rolled in one package
                       DESC
  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version    = '5.7'
  s.platform         = :ios, '15.0'
  s.source_files     = 'Sources/KlaviyoCore/**/*.swift'
end

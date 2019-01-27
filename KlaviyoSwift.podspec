Pod::Spec.new do |s|
  s.name             = "KlaviyoSwift"
  s.version          = "1.4.4"
  s.summary          = "Incorporate Klaviyo's event and person tracking functionality into iOS applications"

  s.description      = <<-DESC
                        Use the Klaviyo SDK to incorporate Klaviyo's event and person tracking functionality within iOS applications. Written in Swift.'
                       DESC

  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = 'MIT'
  s.author           = { "Mobile @ Klaviyo" => "mobile@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }
  s.swift_version = '4.2'
  s.ios.deployment_target = '9.0'
  s.source_files = 'Source/*.swift'
end

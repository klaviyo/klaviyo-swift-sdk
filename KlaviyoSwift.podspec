Pod::Spec.new do |s|
  s.name             = "KlaviyoSwift"
  s.version          = "1.0.4"
  s.summary          = "Incorporate Klaviyo's event and person tracking functionality into iOS applications"

  s.description      = <<-DESC
                        Use the Klaviyo SDK to incorporate Klaviyo's event and person tracking functionality within iOS applications. Written in Swift.'
                       DESC

  s.homepage         = "https://github.com/klaviyo/klaviyo-swift-sdk"
  s.license          = 'MIT'
  s.author           = { "Katy Keuper" => "katy.keuper@klaviyo.com" }
  s.source           = { :git => "https://github.com/klaviyo/klaviyo-swift-sdk.git", :tag => s.version.to_s }

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.source_files = 'Pod/Classes/**/*'
  s.resource_bundles = {
    'KlaviyoSwift' => ['Pod/Assets/*.png']
  }

end

require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-udp-direct"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = { "Juergen Geck" => "juergen@geck.com" }

  s.platforms    = { :ios => "13.0" }
  s.source       = { :git => "https://github.com/lama-app/react-native-udp-direct.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.exclude_files = "ios/build/**/*", "ios/js/**/*"

  s.dependency "React-Core"
  s.dependency "React-RCTNetwork"
  s.dependency "CocoaAsyncSocket", "~> 7.6"
  
  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++20",
    "USE_HEADERMAP" => "YES",
    "HEADER_SEARCH_PATHS" => "\"$(PODS_ROOT)/boost\" \"$(PODS_ROOT)/Headers/Public/React-bridging\" \"$(PODS_ROOT)/Headers/Public/ReactCommon\" \"$(PODS_ROOT)/Headers/Public/React-Codegen\"",
    "OTHER_CPLUSPLUSFLAGS" => "-DFOLLY_NO_CONFIG -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -DRCT_NEW_ARCH_ENABLED=1"
  }
  
  # Add dependencies based on React Native version
  if defined?(install_modules_dependencies)
    install_modules_dependencies(s)
  else
    # Fallback for standard dependencies
    s.dependency "React-cxxreact"
    s.dependency "RCT-Folly"
    s.dependency "RCTRequired"
    s.dependency "RCTTypeSafety"
    s.dependency "ReactCommon/turbomodule/core"
  end
end
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
  
  # Match Expo's proven Folly configuration pattern exactly
  # These flags MUST be applied to every source file BEFORE Folly headers are included
  s.compiler_flags = '-DFOLLY_NO_CONFIG=1 -DFOLLY_MOBILE=1 -DFOLLY_USE_LIBCPP=1 -DFOLLY_CFG_NO_COROUTINES=1 -DFOLLY_HAVE_CLOCK_GETTIME=1 -Wno-comma -Wno-shorten-64-to-32'

  s.pod_target_xcconfig = {
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++17",
    "USE_HEADERMAP" => "YES",
    "HEADER_SEARCH_PATHS" => "\"$(PODS_ROOT)/boost\" \"$(PODS_ROOT)/Headers/Public/React-bridging\" \"$(PODS_ROOT)/Headers/Public/ReactCommon\" \"$(PODS_ROOT)/Headers/Public/React-Codegen\""
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
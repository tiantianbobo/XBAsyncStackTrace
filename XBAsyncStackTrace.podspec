#
#  Be sure to run `pod spec lint AsyncStackTrace.podspec' to ensure this is a
#  valid spec and to remove all comments including this before submitting the spec.
#
#  To learn more about Podspec attributes see http://docs.cocoapods.org/specification.html
#  To see working Podspecs in the CocoaPods repo see https://github.com/CocoaPods/Specs/
#

Pod::Spec.new do |s|

  s.name         = "XBAsyncStackTrace"
  s.version      = "0.1"
  s.summary      = "record iOS async stacktrace"
  s.description  = <<-DESC
  Due to tail call optimization and async func call, there might be a crash that actual crash address will not appear in stack trace. So XBAsyncStackTrace will record dispatch and performSelector's async stack trace,like what you see in Xcode,stack enqueued from blabla, so that you can get to the real crash func
                   DESC
  s.homepage     = "https://github.com/tiantianbobo/XBAsyncStackTrace"
  s.license      = "MIT"
  s.author             = "xiaobochen"
  s.platform     = :ios
  s.platform     = :ios, "8.0"
  s.source       = { :git => "https://github.com/tiantianbobo/XBAsyncStackTrace.git",:tag => "#{s.version}" }
  s.static_framework = true
  s.source_files  = "XBAsyncStackTrace/Classes/*.{h,m}"
  s.public_header_files = "XBAsyncStackTrace/Classes/XBThreadAsyncStackTraceRecord.h","XBAsyncStackTrace/Classes/XBAsyncStackTraceManager.h"
  s.dependency 'fishhook', '~>0.2'

end

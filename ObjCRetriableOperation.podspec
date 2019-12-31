Pod::Spec.new do |spec|
    spec.name     = 'ObjCRetriableOperation'
    spec.version  = '1.0.0'
    spec.license  = 'MIT'
    spec.summary  = 'Make asynchronous components retriable'
    spec.homepage = 'https://github.com/ouyanghua.com/ObjCRetriableOperation'
    spec.author   = { 'ouyanghuacom' => 'ouyanghua.com@gmail.com' }
    spec.source   = { :git => 'https://github.com/ouyanghuacom/ObjCRetriableOperation.git',:tag => "#{spec.version}" }
    spec.description = 'Make asynchronous components retriable.'
    spec.requires_arc = true
    spec.source_files = 'ObjCRetriableOperation/*.{h,m}'
    spec.ios.framework = 'UIKit'
    spec.tvos.framework = 'UIKit'
    spec.ios.deployment_target = '8.0'
    spec.watchos.deployment_target = '2.0'
    spec.tvos.deployment_target = '9.0'
    spec.osx.deployment_target = '10.9'
end

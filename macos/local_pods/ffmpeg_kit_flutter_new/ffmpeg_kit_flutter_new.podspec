Pod::Spec.new do |s|
  s.name         = 'ffmpeg_kit_flutter_new'
  s.version      = '4.1.0'
  s.summary      = 'macOS no-op stub — desktop uses bundled ffmpeg binary directly.'
  s.homepage     = 'https://github.com/antonkarpenko/ffmpeg_kit_flutter'
  s.license      = { :type => 'MIT' }
  s.author       = { 'stub' => 'stub@stub.com' }
  s.source       = { :path => '.' }
  s.source_files = 'Sources/**/*.swift'
  s.platform     = :osx, '10.15'
  s.swift_version = '5.0'
  s.dependency 'FlutterMacOS'
end

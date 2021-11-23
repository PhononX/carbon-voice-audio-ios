Pod::Spec.new do |s|
  s.name             = 'CarbonVoiceAudio'
  s.version          = '1.0.0'
  s.summary          = 'Audio library for CarbonVoice.'

  s.homepage         = 'https://github.com/PhononX/carbon-voice-audio-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE.md' }
  s.author           = { 'Manuel Bulos' => 'manuel@phononx.com' }
  s.source           = { :git => 'https://github.com/PhononX/carbon-voice-audio-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '10.0'
  s.swift_version = '5.0'

  s.source_files = 'Sources/CarbonVoiceAudio/**/*'
end
WINDOZE = false

def install_gem_nodocs name, version = nil
  gem_cmd = Gem.default_exec_format % 'gem'
  sudo    = 'sudo '                  unless WINDOZE
  local   = '--local'                unless version
  version = "--version '#{version}'" if     version
  sh "#{sudo}#{gem_cmd} install #{local} #{name} #{version} --no-rdoc --no-ri"
end

desc 'Install the package as a gem, without docs.'
task :quick => [:clean, :gem, :package] do
  install_gem_nodocs Dir['pkg/*.gem'].first
  puts Time.now
end

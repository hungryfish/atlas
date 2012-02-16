%w[rubygems rake rake/clean fileutils newgem rubigen hoe].each { |f| require f rescue nil } 

require File.dirname(__FILE__) + '/lib/atlas'

# Generate all the Rake tasks
# Run 'rake -T' to see list of generated tasks (from gem root directory)
$hoe = Hoe.spec 'atlas' do |p|
  p.developer('Sean Bowman', 'sean.bowman@publicearth.com')
  p.changes              = p.paragraphs_of("History.txt", 0..1).join("\n\n")
  p.rubyforge_name       = p.name # TODO this is default value
  p.url                  = 'http://www.publicearth.com/'
  p.summary              = 'Db and search for www project'
  p.description          = 'Handles the database and search methods for the www project'
  p.extra_deps         = [
     ['activerecord','2.3.5'],
     ['actionpack','2.3.5'],
     ['activesupport','2.3.5'],
     ['rack', '1.0.1'],
     ['aws-s3', '>= 0.6.2'],
     ['flickraw', '>= 0.7.1'],
     ['libxml-ruby', '>= 1.1.0'],
     ['memcache-client', '>= 1.8.3'],
     ['uuidtools', '>= 2.0.0'],
     ['RedCloth', '>= 4.1.9'],
     ['authlogic', '>= 2.1.3']
  ]
  p.extra_dev_deps = [
    ['newgem', ">= #{::Newgem::VERSION}"],
    ['rspec', ">= 1.2.4"],
    ['rspec-rails', ">= 1.2.4"]
  ]
  
  p.clean_globs |= %w[**/.DS_Store tmp *.log]
  path = (p.rubyforge_name == p.name) ? p.rubyforge_name : "\#{p.rubyforge_name}/\#{p.name}"
  p.remote_rdoc_dir = File.join(path.gsub(/^#{p.rubyforge_name}\/?/,''), 'rdoc')
  p.rsync_args = '-av --delete --ignore-errors'
end

#require 'newgem/tasks' # load /tasks/*.rake
load 'tasks/quick.rake'
#Dir['tasks/**/*.rake'].each { |t| load t }

# TODO - want other tests/tasks run by default? Add them to the list
# task :default => [:spec, :features]


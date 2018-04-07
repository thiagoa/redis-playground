require 'rake/testtask'

Rake::TestTask.new do |i|
  i.libs = ['lib']
  i.test_files = FileList['test/**/test_*.rb']
end
desc 'Run tests'

task default: :test

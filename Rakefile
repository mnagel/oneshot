# rakefile for tictactoe
# further documentation available in the source files
# (rake, rake/clean, rake/testtask, rake/rdoctask)
# and online at the follwing addresses
# http://www.ruby-doc.org/stdlib/libdoc/rdoc/rdoc/index.html
# http://rake.rubyforge.org/classes/Rake/RDocTask.html
# http://rake.rubyforge.org/files/doc/rakefile_rdoc.html
# http://rubyrake.org/index.html

require 'rake'
require 'rake/clean'
require 'rake/testtask'
require 'rake/rdoctask'

# task to be done when building the project...
# example:
#task :default => [:runinshell]
#
#task :runinshell => [] do
#	sh "./lib/launcher.rb"
#end

# to get a task included into the netbeans-rake-list, let it have a description
#desc "some-stupid-desc."
#file "nlr-need-some-file" => ["required-file"] do
#  sh "touch sh-command-file-touched"
#end
#file "required-file" => [] do
#	 sh "touch required-file"
#end

# lists of file something can depend on
#SRC = FileList['*.c']
#OBJ = SRC.ext('o')
# 
# simple rule for many files
#rule '.o' => '.c' do |t|
#  sh "cc -c -o #{t.name} #{t.source}"
#end
#
# file dependency with code block
#file "hello" => OBJ do
#  sh "cc -o hello #{OBJ}"
#end
#  
# file dependencies without code blocks
#file 'main.o' => ['main.c', 'greet.h']
#file 'greet.o' => ['greet.c']

# documentation is clobbered automatically
#CLOBBER.include("doc") 

# example to include c-style o-files in the list of files to clean
# same works with clobber, of course
CLEAN.include('lib/**/*.o')

# the rdoc task(s) (family)
Rake::RDocTask.new do |rd|
	rd.name = :rdoc
	rd.rdoc_dir = "doc"
	rd.main = "README"
	rd.title = "documentation for tictactoe"
	rd.rdoc_files.include("README", "Rakefile", "lib/**/*.rb", "test/**/*.rb")
	rd.options << "--line-numbers" << "--inline-source" << "--diagram" << "--fileboxes"
end

# the test task(s)
Rake::TestTask.new do |t|
	t.libs << "test"
	# tests to run
	t.test_files = FileList['test/testsuite.rb'] 
	t.verbose = true
end

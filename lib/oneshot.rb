#!/usr/bin/env ruby

=begin
    oneshot - simple(?) file uploader
    Copyright (C) 2008 by Michael Nagel

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.

    $Id$

=end

# DONE generate dir-listing
# DONE generate ttl-file
# DONE handle file path. locally allow, remote -> flatten (if local is path and remote nil, or remote path)
# DONE cleanup code
# DONE cleanup switches
# TODO document code
# TODO revise verbosity
# TODO revise fakeness
#
# round 2 :
# DONE handle wrong command line switches
# WONTFIX support scp --> does not allow mkdir...
# TODO remove temporary files in /tmp
# TODO include information about oneshot into html listing
# WONTFIX warn multiple files same name
# DONE handle spaces in filenames, remove(?) sftp does not like them
# TODO above applies for descpription used in URL, too. its ok on html-list, though
# TODO make nicer output (listing html)
# DONE make nicer output (console)
# DONE allow keyboard auth
# TODO revise sftp return code handling
# TODO revise sftp output redirection
# DONE allow generation of config-file
# TODO if local == folder -> warn, let shell glob!
# TODO make remote files world-readable...
# TODO manpages covering: naming files, usage, ... flattening of path
# DONE check if any files...
# DONE handle local files with spaces... cant be read because already escaped...
# DONE generate serverside cleanup tool, removing files that exceed ttl
# 
# round 3 :
# DONE fail if there is no input file...
# TODO disallow executing uploaded scripts on server...
# TODO dont delete listings with files, but keep meta info
# DONE handle umlauts in local filename
#
# round 4:
# DONE size in html listing...
#
# round 5:
# DONE bug with running "... -s " on serverside (crashes)
# DONE add copyright information
#
# round 6:
# DONE print version in help message
# TODO allow file upload via http interface (cgi-script)
#
# round 7:
# TODO simplify remote folder structure
# TODO clean up serverside-check code
# DONE do not load complete file into memory at one time
# DONE upload .expires FIRST (if transfer cancels)

require 'digest/sha1'
require 'time'
require 'date'

# log messages have a level, that decides if they will be printed
LOG_ERROR		= -1
LOG_OUTPUT              =  0
LOG_INFO		=  1
LOG_DEBUG		=  2

# string denoting the current version
THEVERSION = "$Id$, licenced under GPLv3"
# string denoting the date format to be used
DATEFORMAT = "%Y-%m-%d %H:%M:%S"

# reopen the Float class to add some functionality
class Float
  alias_method :orig_to_s, :to_s

  # easier formatted printing, using sprtintf...
  def to_s(arg = nil)
    if arg.nil?
      orig_to_s
    else
      sprintf("%.#{arg}f", self)
    end
  end
end

class String
  # return this string in qoutes
  def quote
    return '"' + self + '"'
  end

  # copied from file lib/shellwords.rb, line 69
  # escapes a string according to sh rules
  def shellescape str = self
    return "''" if str.nil? # added by nailor
    # An empty argument will be skipped, so return empty quotes.
    return "''" if str.empty?

    str = str.dup

    # Process as a single byte sequence because not all shell
    # implementations are multibyte aware.
    str.gsub!(/([^A-Za-z0-9_\-.,:\/@\n])/n, "\\\\\\1")

    # A LF cannot be escaped with a backslash because a backslash + LF
    # combo is regarded as line continuation and simply ignored.
    str.gsub!(/\n/, "'\n'")

    return str
  end

  def asciify
    return self.tr("^A-Za-z0-9_.\-", "_")
  end
end

class Exception
  def show
    STDERR.puts "there was an error: #{self.message}"
    STDERR.puts self.backtrace
  end
end

def hashsum filename
  bufferlength = 1024
  hash = Digest::SHA1.new
  
  open(filename, "r") do |io|
    while (!io.eof)
      readBuf = io.readpartial(bufferlength)
      hash.update(readBuf)
    end
  end
  return hash.hexdigest
end

# send a string to the logging system, with according log level
def log string, loglevel
  puts string unless @options.verbosity < loglevel
end

# build a string of defined length
# pre  : prefix
# char : char to be repeated
# post : postfix
# len  : length of final string, ignored if less then pre+post
def pad pre, char, post, len
  pre = '' if pre.nil?
  post = '' if post.nil?
  return pre + char * [len - pre.length - post.length, 0].max + post
end

# get a nice name (incl. path) for a temporary file
def tempfilename
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..7)
  return "/tmp/oneshot-#{hsh}.htm"
end

# check if directory is empty
def emptydir? dirname
  return Dir.entries(dirname).size == 2
end

# remove a folder if it is empty
def cleanup dir
  if emptydir? dir
    system "rmdir " + dir
    log "cleaned empty folder " + dir, LOG_OUTPUT
  end
end

def serverside_check val
  begin
    dfs = Dir.new(val).sort {|a,b| a.to_s <=> b.to_s}
    dfs.each { |datefolder|
      next if ['.', '..'].include?(datefolder)
      datefolder = File.join(val, datefolder)
      log datefolder, LOG_DEBUG
      
      tfs = Dir.new(datefolder).sort {|a,b| a.to_s <=> b.to_s}
      tfs.each { |titlefolder|
        next if ['.', '..'].include?(titlefolder)
        titlefolder = File.join(datefolder, titlefolder)
        log titlefolder, LOG_DEBUG
        
        hfs = Dir.new(titlefolder).sort {|a,b| a.to_s <=> b.to_s}
        hfs.each { |hashfolder|
          next if ['.', '..'].include?(hashfolder)
          hashfolder = File.join(titlefolder, hashfolder)
          log hashfolder, LOG_DEBUG
          
          path = hashfolder + "/.oneshot-expiry"      
          log "scanning " + path, LOG_DEBUG
          
          begin
            file = File.new(path, "r")
            date = file.gets
            log "best before: " + date, LOG_DEBUG
            
            date = Date.strptime(date, DATEFORMAT)
            ttl = (datify(Time.now) - date).to_i
            if ttl > 0
              log '! ' + hashfolder + ' has expired ' + ttl.to_s + ' days ago', LOG_OUTPUT
              command = "rm -r " + File.expand_path(hashfolder)
              puts "want to execute ' " + command + "'? [yY/$NUMDAYS/nN*]"
              #puts $stdin.gets.chomp

              ans = $stdin.gets.chomp
              if ['y','Y'].include?(ans)
                system command   
              elsif ans.to_i != 0
                expiry = Time.now + ans.to_i * 60 * 60 * 24
                
                File.open(path, 'w+') { |f| f.puts expiry.strftime(DATEFORMAT) }
                log "new expiry: " + expiry.strftime(DATEFORMAT), LOG_OUTPUT
              end
    
            else
              log hashfolder + ' is valid for another ' + (- ttl).to_s + ' days', LOG_INFO
            end
            
          rescue => exc 
            log "error opening " + path, LOG_ERROR
            exc.show
          end
        }

        cleanup titlefolder
      }
      cleanup datefolder
    }
    
  rescue => exc
    log "error scanning for outdated files. are you scanning a oneshot repo?", LOG_ERROR
    exc.show
  end
end

def datify time
  # feel the pain!
  Date.strptime(time.strftime(DATEFORMAT), DATEFORMAT)
end

@options = Struct.new(:title, :ttl, :configfile, :verbosity, :fakeness,
  :host, :user, :port, :prefix, :httppre).new

def options_per_default
  @options.title			= nil
  @options.ttl				= 30
  @options.configfile		= ENV['HOME'] + '/.oneshot-cfg.rb'
  @options.verbosity		= 0
  @options.fakeness			= 0
  @options.host				= nil
  @options.user				= nil
  @options.prefix			= nil
  @options.port             = nil
  @options.httppre			= nil
end

def create_new_config
  file = <<EOT
# put the following in your ~/.oneshot-cfg.rb (change as needed, of course)
# the file is not created automatically, but you can use shell redirection if you want :)
# created by oneshot #{THEVERSION} on #{Time.now.strftime(DATEFORMAT)}
#
@options.title = 'untitled' if @options.title.nil?
# @options.ttl = 30
# @options.configfile = ENV['HOME'] + '/.oneshot-cfg.rb'
# @options.verbosity = 0
# @options.fakeness = 0
@options.host = "myhost.example"  if @options.host.nil?
# @options.user = nil
@options.prefix = "var/www/oneshot/"  if @options.prefix.nil?
# @options.port = nil if @options.port.nil?
@options.httppre = 'http://myhost.example/oneshot/' if @options.httppre.nil?
EOT
end

class Transfer
  attr_accessor :path_local, :path_remote, :description, :url_http
  
  def initialize path_local = nil, path_remote = nil, description = nil, url_http = nil
    @path_local   = path_local
    @path_remote  = path_remote
    @description  = description
    @url_http     = url_http
  end
  
  def path_local escaped = true
    return @path_local unless escaped
    return @path_local.shellescape
  end
end

class Switch
  attr_accessor :char, :comm, :args, :code
  
  def initialize char, comm, args, code
    @char = char
    @comm = comm
    @args = args
    @code = code
  end
end

def options_from_file filename
  begin
    log "gonna load config file", LOG_DEBUG
    log "config file not found", LOG_ERROR unless File.exist?(filename)
    if File.exist?(filename)
      load filename
      log "loaded config file", LOG_INFO
    end
  rescue => exc # FIXME does not seem to work when removing the file.exists?
    log "error loading config file", LOG_ERROR
    STDERR.puts exc.backtrace
  end
end

def options_from_cmd
  log ARGV.join(' '), LOG_DEBUG

  current_transfer = Transfer.new()
  @transfers = []
  switches = nil # for scoping
  @helpswitch = Switch.new('h', 'print help message',	false, proc { puts "this is oneshot #{THEVERSION}"; switches.each { |e| puts '-' + e.char + "\t" + e.comm }; Process.exit })
  switches = [
    Switch.new('f', 'specify remote filename for next file',	true, proc { |val| current_transfer.path_remote = val }),
    Switch.new('d', 'specify remote description for next file', true, proc { |val| current_transfer.description = val }),
    Switch.new('t', 'specify title used in URL',				true, proc { |val| @options.title = val }),

    Switch.new('x', 'specify ttl, remote file can be deleted then', true, proc { |val| @options.ttl = val }),

    Switch.new('c', 'specify local configfile', true, proc { |val| @options.configfile = val }),

    Switch.new('o', 'specify sftp host',        	true, proc { |val| @options.host = val }),
    Switch.new('u', 'specify sftp user',			true, proc { |val| @options.user = val }),
    Switch.new('l', 'specify remote base location',	true, proc { |val| @options.prefix = val }),
    Switch.new('p', 'specify sftp port',			true, proc { |val| @options.port = val }),

    Switch.new('e', 'specify http prefix',	true, proc { |val| @options.httppre = val }),

    Switch.new('v', 'increase verbosity',	false, proc { @options.verbosity += 1 }),
    Switch.new('w', 'increase fakeness',	false, proc { @options.fakeness += 1 }),
		
    Switch.new('i', 'create new config file, nondestructive',   false, proc { log(create_new_config, LOG_OUTPUT) ; Process.exit }),
    Switch.new('s', 'run serverside test, searching outdated files',    true, proc { |val| serverside_check val ; Process.exit }),
    @helpswitch
  ]

  onfile = proc { |filename| current_transfer.path_local = filename; @transfers << current_transfer; current_transfer = Transfer.new()};
  onstuff = proc {|someswitch| log "there is no switch '#{someswitch}'\n\n", LOG_ERROR; @helpswitch.code.call; Process.exit };
  
  
  notargs = [] 

  ARGV.each_index { |i|
    next if notargs.include?(i)

    arg = ''.replace(ARGV[i]) #FIXME: unfreeze

    if arg[0..0] == '-'
      arg[1..-1].scan(/./) do |chr|
        myswitch = switches.find {|s| s.char == chr}
        onstuff.call(chr) if myswitch.nil? 
        if myswitch.args
          myswitch.code.call(ARGV[i+1])
          notargs << i+1
        else
          myswitch.code.call
        end
      end
    else
      onfile.call(ARGV[i])	  
    end
  }
end

def sanatize_options
  @options.title = @options.title.asciify
  @options.ttl = @options.ttl.to_s
  #@options.configfile = ENV['HOME'] + '/.nscripts/oneshot-cfg.rb'
  #@options.verbosity = 0
  #@options.fakeness = 0
  #@options.host = nil
  #@options.user = nil
  @options.prefix = '' if @options.prefix.nil?
  @options.port = @options.port.to_s unless @options.port.nil?
  #@options.httppre = nil
  
  @transfers.each { |t|
    # is escaped now automagically
    # t.path_local  = t.path_local.shellescape 
    t.path_remote = t.path_local(false) if t.path_remote.nil?
    t.path_remote = File.basename(t.path_remote)
    t.path_remote = t.path_remote.asciify.shellescape
  }
end

def print_options
  log "options:\n", LOG_INFO
  @options.each_pair { |name, val|
    name = name.to_s
    val = val.to_s
    log pad(name, ' ', nil, 10) + " = " + val.to_s, LOG_INFO
  }
  
  @transfers.each { |t| 
    tmp  = 'upload: '		+ t.path_local.quote
    tmp += ' goes to '	+ t.path_remote.quote unless t.path_remote.nil?
    tmp += ' tagged '		+ t.description.quote unless t.description.nil?
    log tmp, LOG_INFO
  }
end

# create the list of sftp-commands to be issued
# the path to the index and expiry-file are passed
def create_sftp_commands indexfile, expiryfile
  date = Time.now.strftime("%Y-%m-%d")
  hsh  = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)
	
  cmds  = ""
  cmds += "EOF\n"
  cmds += "-mkdir #{date}\n"
  cmds += "cd #{date}\n"
  cmds += "-mkdir #{@options.title}\n"
  cmds += "cd #{@options.title}\n"
  cmds += "mkdir #{hsh}\n"
  cmds += "cd #{hsh}\n"
  
  # upload the expiry-file first
  cmds += "put #{expiryfile} .oneshot-expiry\n"
  cmds += "put #{indexfile} index.htm\n"
	
  prefix = @options.httppre + date + '/' + @options.title + '/' + hsh + '/'
	
  @transfers.each { |t|
    cmds += "put #{t.path_local} #{t.path_remote}\n"
    cmds += "chmod 644 #{t.path_remote}\n"
    t.url_http = prefix + t.path_remote
  }
  cmds += "EOF\n"
  
  @idxrem = prefix + 'index.htm'
  
  return cmds
end

def generate_dir_list_helper subject, table
  <<EOT
<?xml version="1.0" ?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">

<html xmlns="http://www.w3.org/1999/xhtml">
  <head>
    <title>oneshot - upload - #{subject}</title>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
    <style type="text/css">
      * { 
       font-family: monospace; 
      }
	  ul {
		  padding-bottom: 1.5em;
	  }
    </style>
  </head>
  <body>

    <h1>oneshot - upload - #{subject}</h1>
    <div>
		#{table}
		</div>

  </body>
</html>
EOT
end

def generate_dir_list expiry
  table = @transfers.map { |t|
    temp = ''
    temp += '<h2><a href="' + t.path_remote + '">' + t.path_remote + '</a></h2>'
	
    temp +='<ul>'
		
    temp += '<li>' + t.description + '</li>' unless t.description.nil?
		
    date = Time.now.strftime(DATEFORMAT)
    date2 = expiry.strftime(DATEFORMAT)
    size = (File.size(t.path_local(false)).to_f / (1024*1024)).to_s(3)
    temp += '<li>uploaded: ' + date + '</li>'
    temp += '<li>expires: ' + date2 + '</li>'
    temp += '<li>size ' + size + ' MB</li>'
    
    hash = "sha1: " + hashsum(t.path_local(false))
    temp += '<li>' + hash + '</li>'
		
    temp += "</ul>\n"
  }
	
  result = generate_dir_list_helper @options.title, table
	
  log result, LOG_DEBUG
  return result
end

def run_sftp commands
  real_command = "sftp -C #{@options.host}#{':' + @options.prefix} 1> /dev/null 2>/dev/null << #{commands}"
  log real_command, LOG_INFO
  log '### oneshot: calling sftp ###', LOG_DEBUG
  system real_command if @options.fakeness == 0
  log '### oneshot: called  sftp ###', LOG_DEBUG
  state = $?
  log "command returned: " + state.to_s, LOG_INFO
  log "SFTP ERROR!!!", LOG_ERROR unless state == 0 
  log '----- ----- ----- -----', LOG_INFO
	  
  @transfers.each { |t|
    log t.url_http, LOG_INFO
  } if state == 0
	
  return state
end

begin
  options_per_default
  options_from_cmd
  options_from_file @options.configfile
  
  sanatize_options
  print_options
	
  if @transfers.empty?
    log "found no files to transfer\n\n", LOG_ERROR
    @helpswitch.code.call	
  end
  
  tempfile_list = tempfilename
  tempfile_expire = tempfilename + '.ttl'
  
  expiry = Time.now + @options.ttl.to_f * 60 * 60 * 24
  log "expires on " + expiry.strftime(DATEFORMAT), LOG_INFO
  
  sftp_commands = create_sftp_commands tempfile_list, tempfile_expire
  htmllist = generate_dir_list expiry
  
  File.open(tempfile_list, 'w+') { |f| f.puts htmllist } 
  File.open(tempfile_expire, 'w+') { |f| f.puts expiry.strftime(DATEFORMAT) } 
	
  state = -1
  state = run_sftp sftp_commands
  log @idxrem, LOG_OUTPUT if state == 0
	
rescue => exc
  exc.show
  exit 1
end

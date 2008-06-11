#!/usr/bin/env ruby 

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
# TODO handle local files with spaces... cant be read because already escaped...
# TODO generate serverside cleanup tool, removing files that exceed ttl
# 
# round 3 :
# DONE fail if there is no input file...
# TODO disallow executing uploaded scripts on server...
# TODO dont delete listings with files, but keep meta info

require 'digest/sha1'
require 'time'
require 'date'

LOG_ERROR		= -1
LOG_OUTPUT      =  0
LOG_INFO		=  1
LOG_DEBUG		=  2

THEVERSION = "0.0.5"
DATEFORMAT = "%Y-%m-%d@%H:%M:%S"

def log string, loglevel
  puts string unless @options.verbosity < loglevel
end

def pad pre, char, post, len
  pre = '' if pre.nil?
  post = '' if post.nil?
  return pre + char * [len - pre.length - post.length, 0].max + post
end

def quote string
  return '"' + string + '"'
end

def tempfilename
  hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..7)
  return "/tmp/oneshot-#{hsh}.htm"
end

# file lib/shellwords.rb, line 69
def shellescape(str)
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

def asciify string
  return string.tr("^A-Za-z0-9_.\-", "_")
end

def datify time
  # feel the pain!
  Date.strptime(time.strftime(DATEFORMAT), DATEFORMAT)
end

@options = Struct.new(:title, :ttl, :configfile, :verbosity, :fakeness,
  :host, :user, :port, :prefix, :httppre).new

def serverside_check val
  begin
    
    Dir.new(val).sort {|a,b| a.to_s <=> b.to_s}.each { |datefolder|
      next if ['.', '..'].include?(datefolder)
      datefolder = File.join(val, datefolder)
      log datefolder, LOG_DEBUG
      
      Dir.new(datefolder).sort {|a,b| a.to_s <=> b.to_s}.each { |titlefolder|
        next if ['.', '..'].include?(titlefolder)
        titlefolder = File.join(datefolder, titlefolder)
        log titlefolder, LOG_DEBUG
        
        Dir.new(titlefolder).sort {|a,b| a.to_s <=> b.to_s}.each { |hashfolder|
          next if ['.', '..'].include?(hashfolder)
          hashfolder = File.join(titlefolder, hashfolder)
          log hashfolder, LOG_DEBUG
          
          path = hashfolder + "/.oneshot-expiry"      
          log "scanning " + path, LOG_INFO
          
          begin
            file = File.new(path, "r")
            date = file.gets
            log "best before: " + date, LOG_INFO
            
            date = Date.strptime(date, DATEFORMAT)
            ttl = (datify(Time.now) - date).to_i
            if ttl > 0
              puts 'thats ' + ttl.to_s + ' days ago'
            else
              puts 'thats still ' + (- ttl).to_s + ' days to go...'
            end

          rescue => exc 
            log "error opening " + path, LOG_ERROR
            STDERR.puts exc.backtrace
            STDERR.puts exc.message
          end
        }
      }
    }
    
  rescue => exc
    log "error scanning for outdated files. are you scanning a oneshot repo?", LOG_ERROR
    STDERR.puts exc.backtrace
  end
end

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

Transfer = Struct.new(:path_local, :path_remote, :description, :url_http)
Switch = Struct.new(:char, :comm, :args, :code)

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

  currentTransfer = Transfer.new()
  @transfers = []
  switches = nil # for scoping
  @helpswitch = Switch.new('h', 'print help message',	false, proc { switches.each { |e| puts '-' + e.char + "\t" + e.comm }; Process.exit })
  switches = [
    Switch.new('f', 'specify remote filename for next file',	true, proc { |val| currentTransfer.path_remote = val }),
    Switch.new('d', 'specify remote description for next file', true, proc { |val| currentTransfer.description = val }),
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
		
    Switch.new('i', 'create new config file',   false, proc { log(create_new_config, LOG_OUTPUT) ; Process.exit }),
    Switch.new('s', 'run serverside test, searching outdated files',    true, proc { |val| serverside_check val ; Process.exit }),
    @helpswitch
  ]

  onfile = proc { |filename| currentTransfer.path_local = filename; @transfers << currentTransfer; currentTransfer = Transfer.new()};
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
  @options.title = asciify(@options.title)
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
    t.path_local  = shellescape t.path_local
    t.path_remote = t.path_local if t.path_remote.nil?
    t.path_remote = File.basename(t.path_remote)
    t.path_remote = asciify shellescape(t.path_remote)	
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
    tmp  = 'upload: '		+ quote(t.path_local)
    tmp += ' goes to '	+ quote(t.path_remote) unless t.path_remote.nil? 
    tmp += ' tagged '		+ quote(t.description) unless t.description.nil? 
    log tmp, LOG_INFO
  }
end

def create_sftp_commands tfn, ttlname
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
	
  prefix = @options.httppre + date + '/' + @options.title + '/' + hsh + '/'
	
  @transfers.each { |t|
    cmds += "put #{t.path_local} #{t.path_remote}\n"
    cmds += "chmod 644 #{t.path_remote}\n"
    t.url_http = prefix + t.path_remote
  }
  
  cmds += "put #{tfn} index.htm\n"
  cmds += "put #{ttlname} .oneshot-expiry\n"
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
    temp += '<li>uploaded: ' + date + '</li>'
    temp += '<li>min. online until: ' + date2 + '</li>'

    hash = "sha1: " + Digest::SHA1.hexdigest(File.read(t.path_local))
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
  STDERR.puts "there was an error: #{exc.message}"
  STDERR.puts exc.backtrace
  exit 1
end

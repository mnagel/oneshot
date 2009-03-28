#!/usr/bin/ruby

# TODO run in sandbox (safely)
# TODO problems with spaces...

# TODO include logging -- send mail!

# TODO allow multiple files
# TODO EXCLUDE config

$buffer = ""
$done = false

def puts2 *str
  begin


      puts "Content-Type: text/html\n\n" unless $done
      $done = true


    if str.nil?
      str = ""
    else
      str = str.first
    end
    str = "" if str.nil?
    $buffer += str + "<br />"
  rescue => exc
    $buffer += "<b>something fishy...</b>"
    exc.show
    raise
  end
end

def fire
  puts $buffer
end

begin

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


  #COMMAND = "/home/nailor/bin/oneshot-ng"
  #CONFIGFILE = "/home/nailor/.oneshot-cfg-local.rb"
  STDERR.puts Dir.pwd
  require 'config.rb'

  require 'cgi'
  require 'stringio'

  # send a mail to the authors
  def report_feedback string
    require 'net/http'

    #version: #{CGI::unescapeHTML(get_versionstring).chomp!} killed this line as it is not working-dir independent

    text = CGI::escape <<EOT
TEXT TO MAKE MAIL END HEADERS

#{string}

----- ADDITIONAL INFORMATION -----

EOT

    Net::HTTP.start("nailor.devzero.de") { |http|
      http.get("/quickmail/mail.cgi?str=#{text}&sub=oneshot-upload")
    }

    #  @thanks = "danke für das feedback!<br />"
    #  #@thanks += text
  end

  report_feedback "uploaded something..."

  class Exception
    def show
      STDERR.puts "there was an error: #{self.message}"
      STDERR.puts self.backtrace

      #puts2 "there was an error: #{self.message}"
      #puts2 self.backtrace
    end
  end



#  begin
    require 'digest/sha1'


    def tempfilename
      hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)
      return "/tmp/oneshotupload-#{hsh}.bin"
    end

    cgi = CGI.new("html4")

#    puts2 "BEGIN ORIGINAL FILENAME"
#    puts2 cgi.params['myfile'].first.original_filename
    orig = cgi.params['myfile'].first.original_filename
#    puts2 "END ORIGINAL FILENAME"
#    puts2

#    puts2 "BEGIN LOCAL PATH"
    tmpfile = cgi.params['myfile'].first.path
#    puts2 "END LOCAL PATH"
#    puts2

    thing = cgi.params['myfile'].first
#    puts2 "BEGIN CLASS OF THING"
#    puts2 thing.class.to_s
#    puts2 "END CLASS OF THING"
#    puts2
#
#    #if thing.kind_of? StringIO
#    puts2 "BEGIN STRING IO"
##    begin puts2 thing.to_s; rescue => exc; exc.show end
#    puts2 "TO_S vs. STRING"
##    begin puts2 thing.string; rescue => exc; exc.show end
#    puts2 "END STRING IO"
#    puts2
#    #elsif thing.kind_of? String
#    puts2 "BEGIN PLAIN STRING"
#    puts2 thing
#    puts2 "END PLAIN STRING"
#    puts2
#    #elsif thing.kind_of? File
#    puts2 "BEGIN READ-ABLE FILE"




#    begin #puts2 thing.read;



      fn = tempfilename

      File.open(fn, 'w') { |file| file << thing.read}
      #100.times do puts2 fn end
#      puts2 fn

      #TODO remove file
      #File.safe_unlink(fn)


      filename = fn
      name_it = orig.asciify.shellescape
      cmd = "#{COMMAND} -c #{CONFIGFILE} -f #{name_it} #{filename}"
#      puts2 "running #{cmd}"
      url = %x[#{cmd}]
#      puts2 "command run #{url}" # TODO mail this out, too
#      puts2 "grab your file at <a href=\"#{url}\">#{url}</a>"

#    rescue => exc; exc.show; raise end
#    puts2 "END READ-ABLE FILE"
#    puts2
#    #else
#    puts2 "BEGIN/END UNKNOWN TYPE!!!"
#    #end
#
#    puts2 "END SCRIPT"

    #fromfile = cgi.params['myfile'].first
    #puts2 fromfile.to_s

    #puts2 fromfile.read



    #print '</result>'
#
#  rescue => exc
#    exc.show
#    raise
#  end

  print cgi.header({'status'=>'REDIRECT', 'Location'=>url})


rescue => eee

  fire

end
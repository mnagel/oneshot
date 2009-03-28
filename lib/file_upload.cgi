#!/usr/bin/ruby

# TODO run in sandbox (safely)
# TODO problems with spaces...

# TODO include logging -- send mail!

CONFIGFILE = "/home/nailor/.oneshot-cfg-local.rb"

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

    puts "there was an error: #{self.message}"
    puts self.backtrace
  end
end

def puts2 *str
  begin
    if str.nil?
      str = ""
    else
      str = str.first
    end
    str = "" if str.nil?
    puts str + "<br />"
  rescue => exc
    puts "<b>something fishy...</b>"
    exc.show
  end
end

begin
  require 'digest/sha1'


  def tempfilename
    hsh = Digest::SHA1.hexdigest(rand(2**32).to_s).slice(0..15)
    return "/tmp/oneshotupload-#{hsh}.bin"
  end

  cgi = CGI.new("html4")
  puts "Content-Type: text/html\n\n"

  puts2 "BEGIN ORIGINAL FILENAME"
  puts2 cgi.params['myfile'].first.original_filename
  orig = cgi.params['myfile'].first.original_filename
  puts2 "END ORIGINAL FILENAME"
  puts2

  puts2 "BEGIN LOCAL PATH"
  tmpfile = cgi.params['myfile'].first.path
  puts2 "END LOCAL PATH"
  puts2

  thing = cgi.params['myfile'].first
  puts2 "BEGIN CLASS OF THING"
  puts2 thing.class.to_s
  puts2 "END CLASS OF THING"
  puts2

  #if thing.kind_of? StringIO
  puts2 "BEGIN STRING IO"
  begin puts2 thing.to_s; rescue => exc; exc.show end
  puts2 "TO_S vs. STRING"
  begin puts2 thing.string; rescue => exc; exc.show end
  puts2 "END STRING IO"
  puts2
  #elsif thing.kind_of? String
  puts2 "BEGIN PLAIN STRING"
  puts2 thing
  puts2 "END PLAIN STRING"
  puts2
  #elsif thing.kind_of? File
  puts2 "BEGIN READ-ABLE FILE"




  begin #puts2 thing.read;



    fn = tempfilename

    File.open(fn, 'w') { |file| file << thing.read}
    #100.times do puts2 fn end
    puts2 fn

    #TODO remove file
    #File.safe_unlink(fn)


    filename = fn
    cmd = "/home/nailor/bin/oneshot-ng -c #{CONFIGFILE} -f #{orig} #{filename}"
    puts2 "running #{cmd}"
    a = %x[#{cmd}]
    puts2 "command run #{a}"
    puts2 "grab your file at <a href=\"#{a}\">#{a}</a>"

  rescue => exc; exc.show end
  puts2 "END READ-ABLE FILE"
  puts2
  #else
  puts2 "BEGIN/END UNKNOWN TYPE!!!"
  #end

  puts2 "END SCRIPT"

  #fromfile = cgi.params['myfile'].first
  #puts2 fromfile.to_s

  #puts2 fromfile.read



  #print '</result>'

rescue => exc
  exc.show
end

# Description:
#   This script receives pages in the formats
#        /usr/bin/curl -d host="$HOSTALIAS$" -d output="$SERVICEOUTPUT$" -d description="$SERVICEDESC$" -d type=service -d notificationtype="$NOTIFICATIONTYPE$ -d state="$SERVICESTATE$" $CONTACTADDRESS1$
#        /usr/bin/curl -d host="$HOSTNAME$" -d output="$HOSTOUTPUT$" -d type=host -d notificationtype="$NOTIFICATIONTYPE$" -d state="$HOSTSTATE$" $CONTACTADDRESS1$
#
#   Based on a gist by oremj (https://gist.github.com/oremj/3702073)
#
# Configuration:
#   HUBOT_NAGIOS_URL - https://<user>:<password>@nagios.example.com/cgi-bin/nagios3
#
# Commands:
#   hubot help - display the help text
#

moment      = require 'moment'
Select      = require("soupselect").select
HtmlParser  = require 'htmlparser'
JSDom       = require 'jsdom'
Entities    = require('html-entities').AllHtmlEntities;

nagios_url = process.env.HUBOT_NAGIOS_URL

# remove authentication for using URL inline
safe_url = nagios_url.replace /\/\/(.*):(.*)@/, "//"

# for browser request for bad https
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"

module.exports = (robot) ->

  robot.router.post '/hubot/nagios/:room', (req, res) ->
    room = req.params.room
    host = req.body.host
    output = req.body.output
    state = req.body.state
    notificationtype = req.body.notificationtype

    if req.body.type == 'host'
      robot.messageRoom "#{room}", "nagios #{notificationtype}: #{host} is #{output}"
    else
      service = req.body.description
      robot.messageRoom "#{room}", "nagios #{notificationtype}: #{host}:#{service} is #{state}: #{output}"

    res.writeHead 204, { 'Content-Length': 0 }
    res.end()

  robot.respond /nagios help/i, (msg) ->
    msg.send """
nagios hosts <down|unreachable> - view problem hosts
nagios services <critical|warning|unknown> - view unhandled service issues
nagios host <host> - view host status
nagios ack <host>:<service> <description> - acknowledge alert
nagios downtime <host>:<service> <minutes> - delay the next service notification
nagios check <host>(:<service>) - force check of all services on host (service optional)
nagios enable <host>(:<service>) - enable notifications on host (or specific service optional)
nagios disable <host>(:<service>) - disable notifications on host (or specific service optional)
nagios notifications_off - disables global notifications
nagios notifications_on - enable global notifications
"""

  robot.respond /nagios host (.*)/i, (msg) ->
    host = msg.match[1]
    call = "status.cgi"
    data = "host=#{host}&limit=0"
    nagios_post msg, call, data, (html) ->
      if html.match(/of 0 Matching Services/)
        msg.send "I didn't find any services for a host named '#{host}'"
      else
        service_parse html, (res) -> 
          res = "nagios status for host '#{host}': #{safe_url}/status.cgi?host=#{host}\n" + res
          msg.send res

  robot.respond /nagios ack (.*):(.*) (.*)/i, (msg) ->
    host = msg.match[1]
    service = msg.match[2]
    message = msg.match[3] || ""
    call = "cmd.cgi"
    data = "cmd_typ=34&host=#{host}&service=#{service}&cmd_mod=2&sticky_ack=on&com_author=#{msg.envelope.user}&send_notification=on&com_data=#{encodeURIComponent(message)}"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Your acknowledgement was received by nagios"
      else 
        msg.send "that didn't work.  Maybe a typo?"

  robot.respond /nagios downtime (.*):(.*) (\d+)/i, (msg) ->
    host = msg.match[1]
    service = msg.match[2]
    minutes = msg.match[3] || 30
    call = "cmd.cgi"
    data = "cmd_typ=9&cmd_mod=2&&host=#{host}&service=#{service}&not_dly=#{minutes}"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Muting #{host}:#{service} for #{minutes}m"
      else 
        msg.send "that didn't work.  Maybe a typo?"

  robot.respond /nagios check ([a-zA-z0-9-_]+)$/i, (msg) ->
    host = msg.match[1]
    call = "cmd.cgi"
    start_time = moment().format("YYYY-MM-DD HH:mm:ss")
    data = "cmd_typ=17&cmd_mod=2&host=#{host}&force_check=on&start_time=#{encodeURIComponent(start_time)}"
    nagios_post msg, call, data, (res) ->
      console.log res
      if res.match(/successfully submitted/)
        msg.send "Scheduled to recheck #{host} at #{start_time}"
      else 
        msg.send "that didn't work.  Maybe a typo in the hostname?"

  robot.respond /nagios check (.*):(.*)/i, (msg) ->
    host = msg.match[1]
    service = msg.match[2]
    call = "cmd.cgi"
    start_time = moment().format("YYYY-MM-DD HH:mm:ss")
    data = "cmd_typ=7&cmd_mod=2&host=#{host}&service=#{service}&force_check=on&start_time=#{encodeURIComponent(start_time)}"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Scheduled to recheck #{host}:#{service} at #{readable}"
      else 
        msg.send "that didn't work.  Maybe a typo in the service?"

  robot.respond /nagios enable ([a-zA-z0-9-_]+)$/i, (msg) ->
    host = msg.match[1]
    call = "cmd.cgi"
    data = "cmd_typ=24&cmd_mod=2&host=#{host}"
    nagios_post msg, call, data, (res) ->
      console.log res
      if res.match(/successfully submitted/)
        msg.send "Enabled notifications on #{host}"
      else 
        msg.send "that didn't work.  Maybe a typo in the hostname?"

  robot.respond /nagios enable (.*):(.*)/i, (msg) ->
    host = msg.match[1]
    service = msg.match[2]
    call = "cmd.cgi"
    data = "cmd_typ=22&cmd_mod=2&host=#{host}&service=#{service}"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Enabled notifications for #{host}:#{service}"
      else 
        msg.send "that didn't work.  Maybe a typo in the service?"

  robot.respond /nagios disable ([a-zA-z0-9-_]+)$/i, (msg) ->
    host = msg.match[1]
    call = "cmd.cgi"
    data = "cmd_typ=25&cmd_mod=2&host=#{host}"
    nagios_post msg, call, data, (res) ->
      console.log res
      if res.match(/successfully submitted/)
        msg.send "Disabled notifications on #{host}"
      else 
        msg.send "that didn't work.  Maybe a typo in the hostname?"

  robot.respond /nagios disable (.*):(.*)/i, (msg) ->
    host = msg.match[1]
    service = msg.match[2]
    call = "cmd.cgi"
    data = "cmd_typ=23&cmd_mod=2&host=#{host}&service=#{service}"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Disabled notifications for #{host}:#{service}"
      else 
        msg.send "that didn't work.  Maybe a typo in the service?"

  robot.respond /nagios (notifications_off|stfu|shut up)/i, (msg) ->
    call = "cmd.cgi"
    data = "cmd_typ=11&cmd_mod=2"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Ok, global notifications disabled"

  robot.respond /nagios notifications_on/i, (msg) ->
    call = "cmd.cgi"
    data = "cmd_typ=12&cmd_mod=2"
    nagios_post msg, call, data, (res) ->
      if res.match(/successfully submitted/)
        msg.send "Ok, global notifications are enabled"

nagios_post = (msg, call, data, cb) ->
  msg.http("#{nagios_url}/#{call}")
    .header('accept', '*/*')
    .header('User-Agent', "Hubot/#{@version}")
    .post(data) (err, res, body) ->
      cb body

service_parse = (html, cb) ->
  entities = new Entities()
  handler = new HtmlParser.DefaultHandler()
  parser  = new HtmlParser.Parser handler
  parser.parseComplete html

  results = (Select handler.dom, "td")
  output = ""
  for item in results
    if item['attribs'] && item['attribs']['class'] && item['attribs']['class'].match(/^status/)
      for child in item['children']
        if child['raw'].match(/&service=/)
          output += "`"+child['children'][0]['raw'] + "` "
        if child['raw'].match(/^(OK|WARNING|CRITICAL|UNKNOWN)$/)
          output += "*"+child['raw'] + "* "
          mark = 0
        switch mark
          when 2 then output += "`"+child['raw'] + "` "
          when 4 then output += "\"" + entities.decode(child['raw']) + "\"\n"
    mark += 1
  cb output

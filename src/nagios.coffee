# Description:
#   This script receives pages in the formats
#        /usr/bin/curl -d host="$HOSTALIAS$" -d output="$SERVICEOUTPUT$" -d description="$SERVICEDESC$" -d type=service -d notificationtype="$NOTIFICATIONTYPE$ -d state="$SERVICESTATE$" $CONTACTPAGER$
#        /usr/bin/curl -d host="$HOSTNAME$" -d output="$HOSTOUTPUT$" -d type=host -d notificationtype="$NOTIFICATIONTYPE$" -d state="$HOSTSTATE$" $CONTACTPAGER$
#
#   Example contact pager attribute is like the following:
#     http://<hubot_host>:8080/hubot/nagios/<room_name>
#
#   Based on a gist by bentwr (https://gist.github.com/benwtr/5691225) 
#   which is from a gist by oremj (https://gist.github.com/oremj/3702073)
#
# Configuration:
#   HUBOT_NAGIOS_AUTH - <username>:<password>
#   HUBOT_NAGIOS_URL  - https://nagios.example.com/nagios/cgi-bin
#
# Commands:
#   hubot help - display the help text
#

moment      = require 'moment'
Select      = require("soupselect").select
HtmlParser  = require 'htmlparser'
JSDom       = require 'jsdom'
Entities    = require('html-entities').AllHtmlEntities;

# for browser request for bad https
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0"

# construct various URLs
nagios_url  = process.env.HUBOT_NAGIOS_URL
nagios_auth = process.env.HUBOT_NAGIOS_AUTH
auth = 'Basic ' + new Buffer(nagios_auth).toString('base64');

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

  robot.respond /nagios(NULL|(.*))/i, (msg) ->
    hubot_user = msg['message']['user']['email_address']
    words = msg.match[1]
    input = words.split(' ');
    if words.length < 1
      cmd = 'help' 
    else
      input.shift()
      cmd = input.shift()
     
    switch cmd 

      when 'url'
        msg.send nagios_url.replace(/cgi-bin/, '')

      when 'hosts'
        if input.length < 1 || !input[0].match(/(up|down|unreachable)/i)
          msg.send "Usage: nagios #{cmd} <up|down|unreachable>"
        else
          status = (input[0] || ".*").toUpperCase()
          call = "status.cgi"
          data = "hostgroup=all&style=hostdetail&limit=0"
          info = "#{nagios_url}/#{call}?#{data}"
          nagios_post msg, auth, call, data, (html) ->
              host_parse html, status, (res) -> 
                if res.length > 0
                  res = "#{status} hosts: #{info}\n" + res
                  msg.send res
                else
                  msg.send "I did not find any hosts in '#{status}' state"

      when 'host'
        if input.length < 1 
          msg.send "Usage: nagios #{cmd} <host> [<service>]"
        else
          host = input[0]
          service = input[1] || ".*"
          call = "status.cgi"
          data = "host=#{host}&limit=0"
          info = "#{nagios_url}/#{call}?#{data}"
          console.log nagios_url
          console.log data
          nagios_post msg, auth, call, data, (html) ->
            if html.match(/of 0 Matching Services/)
              msg.send "I didn't find any services for a host named '#{host}'"
            else
              host_service_parse html, 'host', service, (res) -> 
                res = "nagios status for host '#{host}': #{info}\n" + res
                msg.send res

      when 'services'
        if input.length < 1 || !input[0].match(/(critical|warning|unknown)/i)
          msg.send "Usage: nagios #{cmd} <critical|warning|unknown>"
        else
          status = (input[0] || ".*").toUpperCase()
          switch status
            when 'CRITICAL' then sts = '16'
            when 'WARNING'  then sts = '4'
            when 'UNKNOWN'  then sts = '8'
          call = "status.cgi"
          data = "host=all&style=detail&servicestatustypes=#{sts}&limit=0"
          info = "#{nagios_url}/#{call}?#{data}"
          nagios_post msg, auth, call, data, (html) ->
              host_service_parse html, 'services', '.*', (res) -> 
                if res.length > 0
                  res = "#{status} services: #{info}\n" + res
                  msg.send res
                else
                  msg.send "I did not find any services in '#{status}' state"

      when 'ack'
        if input.length < 1 
          msg.send "Usage: nagios #{cmd} <host> [<service>]"
        else
           host = input[0]
           service = input[1]
           if service 
              ct = 34
              service = "&service=#{service}"
           else
              ct = 33
              service = ""
           comment = "hubot initiated ack for #{hubot_user}"
           call = "cmd.cgi"
           data = "cmd_typ=#{ct}&host=#{host}#{service}&cmd_mod=2&sticky_ack=on&com_author=#{encodeURIComponent(hubot_user)}&send_notification=on&com_data=#{encodeURIComponent(comment)}"
           nagios_post msg, auth, call, data, (res) ->
             if res.match(/successfully submitted/)
               msg.send "Your acknowledgement was received by nagios"
             else 
               msg.send "that didn't work.  Maybe a typo?"

      when 'check'
        if input.length < 1 
          msg.send "Usage: nagios #{cmd} <host> [<service>]"
        else
           host = input[0]
           service = input[1]
           if service 
              ct = 7
              serv_ck = "&service=#{service}"
              service = ":#{service}"
           else
              ct = 17
              serv_ck = ""
              service = ""
           start_time = moment().format("YYYY-MM-DD HH:mm:ss")
           call = "cmd.cgi"
           data = "cmd_typ=#{ct}&cmd_mod=2&host=#{host}#{serv_ck}&force_check=on&start_time=#{encodeURIComponent(start_time)}"
           nagios_post msg, auth, call, data, (res) ->
             if res.match(/successfully submitted/)
               msg.send "Scheduled to recheck #{host}#{service} at #{start_time}"
             else 
               msg.send "that didn't work.  Maybe a typo?"

      when 'enable', 'disable'
        if input.length < 1 
          msg.send "Usage: nagios #{cmd} <host> [<service>]"
        else
           host = input[0]
           service = input[1]
           if service 
              serv_ck = "&service=#{service}"
              service = ":#{service}"
              switch cmd 
                when 'enable'  then ct = 22
                when 'disable' then ct = 23
           else
              switch cmd 
                when 'enable'  then ct = 24
                when 'disable' then ct = 25
              serv_ck = ""
              service = ""
           call = "cmd.cgi"
           data = "cmd_typ=#{ct}&cmd_mod=2&host=#{host}#{serv_ck}"
           nagios_post msg, auth, call, data, (res) ->
             if res.match(/successfully submitted/)
               msg.send "Notifications #{cmd}d for #{host}#{service}"
             else 
               msg.send "that didn't work.  Maybe a typo?"
      
      when 'downtime'
        if input.length < 2 
          msg.send "Usage: nagios #{cmd} <host> <service> [<minutes> default: 30]"
        else  
          host = input[0]
          service = input[2]
          minutes = input[3] || 30
          call = "cmd.cgi"
          data = "cmd_typ=9&cmd_mod=2&&host=#{host}&service=#{service}&not_dly=#{minutes}"
          nagios_post msg, auth, call, data, (res) ->
            if res.match(/successfully submitted/)
              msg.send "Downtimed #{host}:#{service} for #{minutes}m"
            else 
              msg.send "that didn't work.  Maybe a typo?"

      when 'notifications', 'notify'
        if input.length < 1 
          msg.send "Usage: nagios #{cmd} <on|off>"
        else  
          mode = input[0]
        switch mode
          when 'on'  
            state = 'enabled'
            ct = 12
          when 'off'  
            state = 'disabled'
            ct = 11
        call = "cmd.cgi"
        data = "cmd_typ=#{ct}&cmd_mod=2"
        nagios_post msg, auth, call, data, (res) ->
          if res.match(/successfully submitted/)
            msg.send "Ok, global notifications #{state}"

      when 'help'
        msg.send """
nagios help:
nagios url - view nagios web url
nagios hosts <up|down|unreachable> - view problem hosts
nagios services [<critical|warning|unknown>] - view non-OK service issues
nagios host <host> [<service>]- view host service status
nagios check <host> [<service>] - force check of all services on host (service optional)
nagios ack <host> [<service>] - acknowledge host or host service
nagios enable <host> [<service>] - (en|dis)able notifications on host (service optional)
nagios disable <host> [<service>] - disable notifications on host (service optional)
nagios downtime <host> <service> [<minutes>] - delay the next service notification
nagios notifications <on|off> - disables global notifications
"""

nagios_post = (msg, auth, call, post, cb) ->
  msg.http("#{nagios_url}/#{call}")
    .header('accept', '*/*')
    .header('Authorization', auth)
    .header('User-Agent', "Hubot/#{@version}")
    .post(post) (err, res, body) ->
      cb body

host_service_parse = (html, type, match, cb) ->
  entities = new Entities()
  handler = new HtmlParser.DefaultHandler()
  parser  = new HtmlParser.Parser handler
  parser.parseComplete html

  results = (Select handler.dom, "td")
  output = ""
  host = ""
  for item in results
    if item['attribs'] && item['attribs']['class'] && item['attribs']['class'].match(/^status/)
      for child in item['children']
        if type == 'services' && child['attribs'] && 
           child['attribs']['href']  &&
           child['attribs']['href'].match(/1&host=/)
          host = "*#{child['children'][0]['raw']}*"
        if child['raw'].match(/&service=/)
          service = child['children'][0]['raw']
          buffer = "#{host} `#{service}` "
        if child['raw'].match(/^(OK|WARNING|CRITICAL|UNKNOWN)$/)
          buffer += "*#{child['raw']}* "
          mark = 0
        switch mark
          when 2, 3 then buffer += "`"+child['raw'] + "` "
          when 4 
            buffer += "\"" + entities.decode(child['raw']) + "\"\n"
            if service.match(match) then output += buffer
    mark += 1
  cb output

host_parse = (html, match, cb) ->
  entities = new Entities()
  handler = new HtmlParser.DefaultHandler()
  parser  = new HtmlParser.Parser handler
  parser.parseComplete html

  results = (Select handler.dom, "td")
  output = ""
  for item in results
    if item['attribs'] && item['attribs']['class'] && item['attribs']['class'].match(/^status/)
      for child in item['children']
        if child['raw'].match(/&host=/)
          buffer = "`"+child['children'][0]['raw'] + "` "
        if child['raw'].match(/^(UP|DOWN|UNREACHABLE)$/)
          status = child['raw']
          buffer += "*#{status}* "
          mark = 0
        if mark == 2
            buffer += "`"+child['raw'] + "`\n"
            if status.match(match) then output += buffer
    mark += 1
  cb output

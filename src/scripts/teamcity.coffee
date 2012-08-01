# show me builds -- Show status of 3 most recent builds
# run build -- Run gogobot build
# deploy to staging -- Deploys master to staging

http = require "http"
Robot   = require("hubot").robot()

module.exports = (robot) ->
  username = process.env.HUBOT_TEAMCITY_USERNAME
  password = process.env.HUBOT_TEAMCITY_PASSWORD
  hostname = process.env.HUBOT_TEAMCITY_HOSTNAME

  parseBuildPayload = (data, callback) ->
    buildStatus = data.build.buildStatus
    buildResult = data.build.buildResult
    buildNum    = data.build.buildNumber
    buildName   = data.build.buildName
    projName    = data.build.projectName
    message     = data.build.message

    if message
      callback message
    else 
      msg = switch buildResult
        when "running"
          "started"
        when "success"
          "successful (#{buildStatus})"
        when "failure"
          if buildStatus is "Will Fail"
            "will fail, please check configuration"
          else
            "failed (#{buildStatus})"

      callback "Build #{buildNum} of #{projName}/#{buildName} #{msg}"

  server = http.createServer (req, res) =>
    if req.url is "/build"
      data = ""
      req.setEncoding "utf8"

      req.on "data", (chunk) ->
        data += chunk

      req.on "end", ->
        user = robot.userForId 'broadcast'
        user.room = process.env.HUBOT_CAMPFIRE_ROOMS.split(",")[0]
        user.type = 'groupchat'
        parseBuildPayload JSON.parse(data), (message) ->
          robot.receive new Robot.TextMessage user, "TeamCity notification: #{message}"
        
      res.writeHead 200, {'Content-Type': 'text/plain'}
      res.end 'OK'

  server.listen (parseInt(process.env.PORT) or 3000), "0.0.0.0"

  robot.hear /TeamCity notification: (.*)/i, (msg) ->
    msg.send msg.match[0]

  robot.respond /deploy (.*)( to|to) (staging|stg)/i, (msg) ->
    buildTypeId = "bt3"
    branch = msg.match[1]

    if branch.trim() == ""
      msg.send "You need to tell me which branch you me want to deploy to staging."
    else
      msg.http("http://#{hostname}/httpAuth/action.html?add2Queue=#{buildTypeId}&name=env.BRANCH&value=#{branch}")
        .headers(Authorization: "Basic #{new Buffer("#{username}:#{password}").toString("base64")}", Accept: "application/json")
        .get() (err, res, body) ->
          msg.send "Deploying #{branch} to staging."

  robot.respond /run build/i, (msg) ->
    buildTypeId = "bt2"

    msg.http("http://#{hostname}/httpAuth/action.html?add2Queue=#{buildTypeId}")
      .headers(Authorization: "Basic #{new Buffer("#{username}:#{password}").toString("base64")}", Accept: "application/json")
      .get() (err, res, body) ->
        msg.send "Build triggered in TeamCity."

  robot.respond /show (me )?builds/i, (msg) ->
    msg.http("http://#{hostname}/app/rest/builds")
      .query(locator: ["running:any", "count:3"].join(","))
      .headers(Authorization: "Basic #{new Buffer("#{username}:#{password}").toString("base64")}", Accept: "application/json")
      .get() (err, res, body) ->
        if err
          msg.send "Team city says: #{err}"
          return
        # Sort by build number.
        builds = JSON.parse(body).build.sort((a, b)-> parseInt(b.number) - parseInt(a.number))

        displayBuild = (msg, build) ->
          msg.http("http://#{hostname}#{build.href}")
            .headers(Authorization: "Basic #{new Buffer("#{username}:#{password}").toString("base64")}", Accept: "application/json")
            .get() (err, res, body) ->
              if err
                msg.send "Team city says: #{err}"
                return

              project = JSON.parse(body)

              statusText = if build.statusText then ": #{build.statusText}." else ''

              if build.running
                started = Date.parse(build.startDate.replace(/(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})([+\-]\d{4})/, "$1-$2-$3T$4:$5:$6$7"))
                elapsed = (Date.now() - started) / 1000
                seconds = "" + Math.floor(elapsed % 60)
                seconds = "0#{seconds}" if seconds.length < 2
                msg.send "#{project.buildType.projectName} - #{project.buildType.name} - \##{build.number}, #{build.percentageComplete}% complete, #{Math.floor(elapsed / 60)}:#{seconds} minutes elapsed#{statusText}"
              else if build.status is "SUCCESS"
                msg.send "#{project.buildType.projectName} - #{project.buildType.name} - \##{build.number} is SUCCESS#{statusText}"
              else if build.status is "FAILURE"
                msg.send "#{project.buildType.projectName} - #{project.buildType.name} - \##{build.number} FAILED#{statusText}"

        for build in builds
          displayBuild(msg, build)

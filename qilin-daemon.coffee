#!/usr/bin/env coffee

process.env.QILIN_LOG_LEVEL = if process.env.NODE_ENV is 'production' then 'warning' else 'info'
async = require 'async'
http = require 'http'
url = require 'url'
path = require 'path'
watch = require 'node-watch'
fs = require 'fs'
{argv} = require 'optimist'
Qilin = require 'qilin'

# usage isnt necessary on windows
try
  usage = require 'usage'
catch e
  usage = lookup: (pid, cb) -> cb()

### read 'qilin-daemon.json' ###
try
  json = argv._[0] ? "#{process.cwd()}/qilin-daemon.json"
  config = require json
  process.chdir path.dirname(json)
catch e
  console.log e.message
  process.exit 1

### default config values ###
throw new Error "no such exec file: '#{config.exec}'" unless fs.existsSync config.exec
config.args ?= []
config.workers ?= 1
config.silent ?= false
config.worker_disconnect_timeout ?= 5000
config.watch ?= []
config.reload_delay ?= 10000

### functions ###

# human readable numeric
hmem = (m = 0) -> Math.ceil(m / 1024 / 1024 * 100) / 100
hcpu = (c = 0) -> Math.ceil(c * 100) / 100
htime = (t = 0) ->
  t = Math.floor(t)
  days = Math.floor(t / 86400)
  t %= 86400
  hours = Math.floor(t / 3600)
  t %= 3600
  mins = Math.floor(t / 60)
  t %= 60
  secs = t
  days: days
  hours: hours
  minutes: mins
  seconds: secs

# daemon message
dmessage = (msg) -> console.log "[daemon] #{msg}"

# remove pidfile on quit
quit = () ->
  fs.unlinkSync argv.pidfile if argv.pidfile and fs.existsSync argv.pidfile
  process.exit 0

### ps_name ###
process.title = config.ps_name if config.ps_name?

### pidfile ###
if argv.pidfile
  fs.writeFileSync argv.pidfile, process.pid
  process.on 'SIGINT', () -> quit()
  process.on 'SIGTERM', () -> quit()

### qilin start ###
opt =
  exec: config.exec
  args: config.args
  silent: config.silent

qilin = new Qilin opt, workers: config.workers
qilin.start () ->
  ### watch files ###
  wTimer = null
  config.watch.push config.exec
  watch config.watch, { recursive: false, followSymLinks: true }, (filename) ->
    lastchange = new Date()
    return if wTimer?
    wTimer = setInterval () ->
      if (new Date()) - lastchange > config.reload_delay
        methods.reload()
        clearInterval wTimer
        wTimer = null
    , 1000

  ### daemon methods ###
  methods =
    help: (cb) ->
      cb? null,
        reload: 'restart worker processes'
        stats: 'get server status (memory, cpu, etc)'
        quit: 'shutdown server (with workers)'

    reload: (cb) ->
      cluster = qilin.listeners?.exit?[0].target
      unless cluster?
        # can't get cluster for some reason
        qilin.killWorkers true, () ->
          qilin.forkWorkers () ->
            dmessage 'restart workers'
            cb? null, 'OK'
        return

      # force destroy check timer
      destroyTimers = {}
      for i, w of cluster.workers
        destroyTimers[w.id] = setTimeout () ->
          w.destroy()
          dmessage "force destroy Worker[#{w.id}]"
        , config.worker_disconnect_timeout

      cluster.on 'exit', (worker, code, signal) ->
        dTimer = destroyTimers[worker.id]
        if dTimer
          clearTimeout dTimer
          delete destroyTimers[worker.id]
          if Object.keys(destroyTimers).length is 0
            qilin.forkWorkers () ->
              dmessage 'restart workers'
              cb? null, 'OK'

      qilin.killWorkers false

    stats: (cb) ->
      cluster = qilin.listeners.exit[0].target
      usage.lookup process.pid, (merr = {}, result = {}) ->
        stats =
          master:
            pid: process.pid
            cpu: hcpu result.cpu
            mem: hmem result.memory
            uptime: htime process.uptime()
          workers: []
        stats.total =
          cpu: stats.master.cpu
          mem: stats.master.mem

        async.each (cw.process for i, cw of cluster.workers), (item, next) ->
          usage.lookup item.pid, (err, result = {}) ->
            tmp =
              pid: item.pid
              cpu: hcpu result.cpu
              mem: hmem result.memory
            stats.workers.push tmp
            stats.total.cpu += tmp.cpu
            stats.total.mem += tmp.mem
            next()
        , (err) ->
          stats.total.cpu = hcpu stats.total.cpu
          stats.total.mem = hcpu stats.total.mem
          cb merr, stats

    quit: (cb) ->
      qilin.shutdown true, () -> cb null, 'OK'

  ### manager daemon http interface ###
  if config.daemon_port
    send = (res, data = {}, status = 200) ->
      res.writeHead status, { 'Content-Type': 'application/json; charset=utf-8', 'Connection': 'close' }
      res.end JSON.stringify data

    http.createServer (req, res) ->
      # basic auth
      if config.auth_username and config.auth_password
        token = (req.headers.authorization ? '').split(/\s+/).pop() ? ''
        auth = new Buffer(token, 'base64').toString()
        [ username, password ] = auth.split /:/
        if config.auth_username isnt username or config.auth_password isnt password
          res.setHeader 'WWW-Authenticate', 'Basic realm="qilin-daemon auth"'
          return send res, { error: 'unauthorized' }, 401

      ui = url.parse req.url, true
      m = ui.pathname.substr(1)
      unless methods[m]?
        return send res, { error: 'unknown method' }, 404
      methods[m] (err = {}, result) ->
        send res, { error: err.message, result: result }
        quit() if m is 'quit'
    .listen config.daemon_port

  message = "#{opt.exec} x #{config.workers} started"
  message += " (daemon_port: #{config.daemon_port})"  if config.daemon_port
  dmessage message

  process.on 'exit', () -> dmessage 'exit'

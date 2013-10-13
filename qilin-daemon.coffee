#!/usr/bin/env coffee

process.env.QILIN_LOG_LEVEL = if process.env.NODE_ENV is 'production' then 'warning' else 'info'
async = require 'async'
http = require 'http'
url = require 'url'
path = require 'path'
watch = require 'node-watch'
fs = require 'fs'
Qilin = require 'qilin'

# usage isnt necessary on windows
try
  usage = require 'usage'
catch e
  usage = lookup: (pid, cb) -> cb()

### read 'qilin-daemon.json' ###
try
  json = process.argv[2] ? "#{process.cwd()}/qilin-daemon.json"
  config = require json
  process.chdir path.dirname(json)
catch e
  console.log e.message
  process.exit()

### default config values ###
throw new Error "no such exec file: '#{config.exec}'" unless fs.existsSync config.exec
config.args ?= []
config.workers ?= 1
config.silent ?= false
config.worker_disconnect_timeout ?= 5000
config.watch ?= []
config.reload_delay ?= 10000

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

  ### human readable numeric funcs ###
  hmem = (m = 0) -> Math.ceil(m / 1024 / 1024 * 100) / 100
  hcpu = (c = 0) -> Math.ceil(c * 100) / 100

  ### daemon message func ###
  dmessage = (msg) -> console.log "[daemon] #{msg}"
  
  ### daemon methods ###
  methods =
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
  
    info: (cb) ->
      cluster = qilin.listeners.exit[0].target
      info =
        master: {}
        workers: []
        total: {}
  
      usage.lookup process.pid, (merr = {}, result = {}) ->
        info.master.pid = process.pid
        info.master.cpu = hcpu result.cpu
        info.master.mem = hmem result.memory
        info.total.cpu = info.master.cpu
        info.total.mem = info.master.mem
  
        async.each (cw.process for i, cw of cluster.workers), (item, next) ->
          usage.lookup item.pid, (err, result = {}) ->
            tmp =
              pid: item.pid
              cpu: hcpu result.cpu
              mem: hmem result.memory
            info.workers.push tmp
            info.total.cpu += tmp.cpu
            info.total.mem += tmp.mem
            next()
        , (err) ->
          info.total.cpu = hcpu info.total.cpu
          info.total.mem = hcpu info.total.mem
          cb merr, info
  
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
          return send res, { error: 'unauthorized' }, 401

      ui = url.parse req.url, true
      m = ui.pathname.substr(1)
      unless methods[m]?
        return send res, { error: 'unknown method' }, 404
      methods[m] (err = {}, result) ->
        send res, { error: err.message, result: result }
        process.exit() if m is 'quit'
    .listen config.daemon_port

  message = "#{opt.exec} x #{config.workers} started"
  message += " (daemon_port: #{config.daemon_port})"  if config.daemon_port
  dmessage message

  process.on 'exit', () -> dmessage 'exit'

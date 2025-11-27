path       = require('path')
express    = require('express')
_          = require('lodash')
Doxx       = require('@balena/doxx')
navTree    = require('./nav.json')
config     = require('../config')
redirect   = require('./redirect')({ pathPrefix: config.pathPrefix })
doxxConfig = require('../config/doxx')
redirectToHTTPS = require('express-http-to-https').redirectToHTTPS

app = express()
app.use(redirectToHTTPS([/localhost:(\d{4})/]))

# Body parsers for subscription proxy
app.use express.json()
app.use express.urlencoded(extended: false)

doxx = Doxx(doxxConfig)
doxx.configureExpress(app)

{ GOOGLE_VERIFICATION } = process.env
if GOOGLE_VERIFICATION
  if not GOOGLE_VERIFICATION.match(/\.html$/)
    GOOGLE_VERIFICATION += '.html'
  app.use "/#{GOOGLE_VERIFICATION}", (req, res) ->
    res.send("google-site-verification: #{GOOGLE_VERIFICATION}")

staticDir = path.join(__dirname, '..', 'static')
contentsDir = path.join(__dirname, '..', config.docsDestDir)

app.use("#{config.pathPrefix}/", express.static(staticDir))

app.use (req, res, next) ->
  originalUrl = req.originalUrl
  url = redirect(originalUrl)

  if url isnt originalUrl
    return res.redirect(url)
  next()

getLocals = (extra) ->
  doxx.getLocals({ nav: navTree }, extra)

console.error('serving everything under pathPrefix:', "#{config.pathPrefix}")
app.use("#{config.pathPrefix}/", express.static(contentsDir))

# Server-side proxy for newsletter subscriptions to keep API keys secret.
app.post "#{config.pathPrefix}/subscribe", (req, res) ->
  try
    endpoint = process.env.CONVERTKIT_API_ENDPOINT || config.layoutLocals?.convertkit_api_endpoint || ''
    apiKey = process.env.CONVERTKIT_API_KEY || config.layoutLocals?.convertkit_api_key || ''

    if not endpoint
      return res.status(500).json({ error: 'ConvertKit endpoint not configured' })

    email = req.body?.email || req.body?.email_address || req.query?.email
    if not email
      return res.status(400).json({ error: 'Missing email' })

    payload = { email: email }
    headers = { 'Content-Type': 'application/json' }
    if apiKey then headers['X-API-KEY'] = apiKey

    fetchFn = global.fetch || require('node-fetch')

    fetchFn(endpoint,
      method: 'POST'
      headers: headers
      body: JSON.stringify(payload)
    ).then (r) ->
      r.text().then (bodyText) ->
        res.status(r.status).send(bodyText)
    .catch (err) ->
      console.error('subscribe proxy error', err)
      res.status(502).json({ error: 'Subscription proxy failed' })
  catch err
    console.error('subscribe route error', err)
    res.status(500).json({ error: 'Internal server error' })

app.get '*', (req, res) ->
  res.redirect("#{config.pathPrefix}/404")

port = process.env.PORT ? 3000

app.listen port, ->
  console.log("Server started on http://localhost:#{port}")

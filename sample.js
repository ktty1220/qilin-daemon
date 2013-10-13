var http = require('http');

http.createServer(function (req, res) {
  res.writeHead(200, {'Content-Type': 'text/plain'});
  console.log('hoge');
  console.error('fuga');
  res.end('Hello World\n');
})
.listen(3000);

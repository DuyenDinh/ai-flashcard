import http.server, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
http.server.SimpleHTTPRequestHandler.extensions_map.update({'.js':'application/javascript','.css':'text/css'})
httpd = http.server.HTTPServer(('', 3000), http.server.SimpleHTTPRequestHandler)
print("Serving on http://localhost:3000", flush=True)
httpd.serve_forever()

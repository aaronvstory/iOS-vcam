from flask import Flask, request, Response
from datetime import datetime
import email.utils

app = Flask(__name__)

RESPONSE_TEXT = "rEwfWN3kR+fL5HfrfwJxTBsbAgLkF1IAU40oJza3rLfGiqJBEHbR4Qss52wfWK4I/HabEpShV2d/ckX8VLblti/FGqDBAgQgKd8WNlb59I8="

@app.route('/', defaults={'path': ''}, methods=['POST'])
@app.route('/<path:path>', methods=['POST'])
def handle_post(path):
    print(f"Received POST on /{path}")

    headers = {
        "Content-Type": "application/json",
        "Content-Length": str(len(RESPONSE_TEXT)),
        "Server": "cloudflare",
        "Encrypt-Body": "true",
        "Cf-Cache-Status": "DYNAMIC",
        "Vary": "accept-encoding",
        "Strict-Transport-Security": "max-age=2592000; includeSubDomains; preload",
        "X-Content-Type-Options": "nosniff",
        "Report-To": '{"group":"cf-nel","max_age":604800,"endpoints":[{"url":"https://a.nel.cloudflare.com/report/v4?s=vowRzgPoQ%2F%2FGqkqfmuq5tTQFxoiKvpOwmdTLLKpPEWGEk%2FSrYaEDXEihKsdi3X%2BKXMXX9KprKQm3qMfMJh5Kwy4UpfmpCAn2eqRcMQ%3D%3D"}]}',
        "Nel": '{"report_to":"cf-nel","success_fraction":0.0,"max_age":604800}',
        "Cf-Ray": "96e0c91fbe750039-LHR",
        "Alt-Svc": 'h3=":443"; ma=86400',
        "Date": email.utils.formatdate(usegmt=True),
    }

    return Response(RESPONSE_TEXT, headers=headers, status=200)

if __name__ == '__main__':
    import os
    import sys
    
    # Get host from environment variable or command line
    host = os.environ.get('FLASK_HOST', '0.0.0.0')
    
    # Check for --host argument
    for i, arg in enumerate(sys.argv):
        if arg == '--host' and i + 1 < len(sys.argv):
            host = sys.argv[i + 1]
            break
    
    print(f"Starting Flask server on {host}:80")
    app.run(host=host, port=80)
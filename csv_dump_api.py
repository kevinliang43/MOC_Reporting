from flask import Flask
from flask import request

app = Flask(__name__)

@app.route('/csvdata')
def index():
    return "Hello World"

"""
@app.route('/csvdata', methods = ['POST'])
def csv_dump():
    if request.method == 'POST':
        params = request.get_json()
        # Check params
        field_check = all(field in params for field in ["start_ts", "end_ts", "type", "name"])
        size_check = len(params.items()) == 4
        #TODO: Add Auth with username/password
        if field_check and size_check:
            # Run csv dump
"""            
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)
    

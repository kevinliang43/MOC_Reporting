import argparse
import os
from datetime import datetime
from shutil import make_archive, rmtree
from io import StringIO
from utils import get_connection
from flask import Flask, request, Response, send_file, after_this_request
from csv_dump import query_and_write_data, get_tables, write_table_output
from query_info import QueryInfo
from utils import get_config


app = Flask(__name__)
config = get_config() 

def param_check(params):
    """ Checks the JSON parameters for a given POST request for CSV dump

        Checks:
            Field Checks: JSON should include the following fields: ["start_ts", "end_ts", "type", "name"]
            Size Check: JSON should have 4 parameters
            type_field_check: "type" field should be one of: ["institution", "project"]

        Args:
            params (dict): JSON parameters from the POST request

        Returns:
            Boolean representing whether the JSON parameters pass the checks
    """
    field_check = all(field in params for field in ["start_ts", "end_ts", "type", "name"])
    size_check = len(params.items()) == 4
    type_field_check = params["type"] in ["institution", "project"]
    # TODO: Add format check of start_ts and end_ts

    return field_check and size_check

@app.route('/csvdata/<table>', methods = ['POST'])
def csv_dump_table(table):
    """ Returns a REST response containing csv dump of a single table from the MOC reporting database that is filtered on:
        1. start_timestamp - beginning timestamp of the csv dump
        2. end_timestamp - end timestamp of the csv dump
        3. type - type of the dump required (either an "institution" or "project" filtered dump)
        4. name - name/id of the project/institution (either int or string)
    """
    response = None
  
    if request.method == 'POST':
        params = request.get_json()
    
        if not param_check(params):
            response = Response("Bad Request", 400)
        else:
            #TODO: Add Auth with username/password
            """
            elif not auth:
              response = Response("Auth Failed", 401)
            """
            if params["type"] == "project":
                query = QueryInfo.get_query_infos_by_project(params["name"])
            elif params["type"] == "institution":
                query = QueryInfo.get_query_infos_by_institution(params["name"])

            if query is None:
                response = Response("Invalid query type: " + params["type"], 404)
            else:
                conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
                s = StringIO()
                """ TODO: This section needs to be refactored/cleaned up:
                    - WSGI doesn't like Chunked Transfer-Encoding: 
                        <https://www.python.org/dev/peps/pep-3333/#other-http-features>
                        <https://github.com/pallets/flask/issues/367>
                        Possible workaround with iterators:
                        <https://dev.to/rhymes/comment/2inm>
                    - Not clear how to stick a Writer (input to write_table_output)
                        to a Reader (input to Response)
                """
                write_table_output(conn.cursor(), query, s)
                response = Response(s.getvalue(), 200, mimetype='text/csv')
    else:
        response = Response("Endpoint requires POST", 405)


@app.route('/csvdata', methods = ['POST'])
def csv_dump():
    """ Returns an archived (zip) csv dump of the MOC reporting database that is filtered on:
        1. start_timestamp - beginning timestamp of the csv dump
        2. end_timestamp - end timestamp of the csv dump
        3. type - type of the dump required (either an "institution" or "project" filtered dump)
        4. name - name/id of the project/institution (either int or string)

        Example request:

        curl -H "Content-type: application/json; charset=utf-8"
             -X POST http://<host_ip>:<port_ip>/csvdata 
             -o archive.zip 
             -d '{"start_ts":"2019-01-01","end_ts":"2019-04-01","type":"project","name":1}'

        Returns:
            Archived csv dump to the client that made the request.
    """

    response = None

    if request.method == 'POST':
        params = request.get_json()
        if not param_check(params):
            response = Response("Bad Request", 400)
        else:
            query = None
            #TODO: Add Auth with username/password
            
            # Connection to database
            conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
            cur = conn.cursor()

            # File name and Path Parameters for dump
            current_ts = datetime.now().strftime("%m_%d_%Y_%H:%M:%S")
            base_path = "{}/api_temp_dump".format(os.getcwd())

            temp_path = "{}/{}/".format(base_path, current_ts)
            archive_file_name = "{}_{}_{}_archive".format(params["name"], params["start_ts"], params["end_ts"])
            archive_path = "{}/{}".format(base_path, archive_file_name)
            
            # Determine Query of Project/Institution
            if params["type"] == "project":
                query = QueryInfo.get_query_infos_by_project(params["name"], params["start_ts"], params["end_ts"])
        
            elif params["type"] == "institution":
                query = QueryInfo.get_query_infos_by_institution(params["name"], params["start_ts"], params["end_ts"])

            # Query is invalid
            if query is None:
                response = Response("Invalid query type: " + params["type"], 404)

            # Query and write dump to temp_path
            else:
                for query_info in query:
                    query_and_write_data(cur, query_info, temp_path, "{}_{}".format(params["start_ts"], params["end_ts"]))
                
                # Create zip archive of dump
                make_archive(archive_path, "zip", temp_path)
                
                @after_this_request
                def remove_archive(response):
                    try:
                        # remove temp_path
                        rmtree(base_path)    
                    except Exception as e:
                        app.logger.error("Failed to remove temp dump directory", e)
                    return response
                        

                # SEND
                return send_file("{}.zip".format(archive_path), attachment_filename=archive_file_name)
                
                

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default=80, type=int)
    args = parser.parse_args()
    app.run(host='0.0.0.0', port=args.port)
  

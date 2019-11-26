
import argparse
import os
from datetime import datetime

from shutil import make_archive, rmtree
from io import StringIO
from utils import get_connection
from flask import Flask, request, Response

from csv_dump import query_and_write_data, get_tables, write_table_output
from query_info import QueryInfo
from utils import get_config


app = Flask(__name__)
config = get_config() 

def param_check(params):
    # Check params
    field_check = all(field in params for field in ["start_ts", "end_ts", "type", "name"])
    size_check = len(params.items()) == 4
   
    return field_check and size_check

@app.route('/csvdata/<table>', methods = ['POST'])
def csv_dump_table(table):
    response = None

  
    if request.method == 'POST':
        params = request.get_json()
    
        if not param_check(params):
            response = Response("Bad Request", 400)
        else:
            return
    #TODO: Add Auth with username/password
    """
    elif not auth:
      response = Response("Auth Failed", 401)
    """
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
    """
    """ TODO: This is gross; I'd prefer to stream but that's been difficult:
          - WSGI doesn't like Chunked Transfer-Encoding: 
            <https://www.python.org/dev/peps/pep-3333/#other-http-features>
            <https://github.com/pallets/flask/issues/367>
            Possible workaround with iterators:
            <https://dev.to/rhymes/comment/2inm>
          - Not clear how to stick a Writer (input to write_table_output)
            to a Reader (input to Response)
      """
    """
      write_table_output(conn.cursor(), query, s)
      response = Response(s.getvalue(), 200, mimetype='text/csv')
  else:
    response = Response("Endpoint requires POST", 405)

  return response
 """

@app.route('/csvdata', methods = ['POST'])
def csv_dump():
    response = None

    if request.method == 'POST':
        params = request.get_json()
        print(params) 
        if not param_check(params):
            print("BAD PARAMS")
            response = Response("Bad Request", 400)
        else:
            print("GOOD PARAMS")
            query = None
            #TODO: Add Auth with username/password
            """
            elif not auth:
              response = Response("Auth Failed", 401)
            """
            # Connection to database
            conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
            cur = conn.cursor()

            # Parameters for dump
            temp_path = "{}/api_temp_dump/{}".format(os.getcwd(), datetime.now().strftime("%m_%d_%Y_%H:%M:%S"))
            archive_path = temp_path + "/archive.zip"

            if params["type"] == "project":
                query = QueryInfo.get_query_infos_by_project(params["name"], params["start_ts"], params["end_ts"])
        
            elif params["type"] == "institution":
                query = QueryInfo.get_query_infos_by_institution(params["name"], params["start_ts"], params["end_ts"])

            if query is None:
                response = Response("Invalid query type: " + params["type"], 404)

            # Query and write output to temp path
            else:
                for query_info in query:
                    query_and_write_data(cur, query_info, temp_path, "{}_{}".format(params["start_ts"], params["end_ts"]))
                
                return Response("QUERY WORKS OK", 200)
                
                """
                # Zip path and load to memory
                make_archive(archive_path, "zip", temp_path)

                with open(archive_path) as dump_archive:
                    data = dump_archive.read()
                """

    # SEND
    #response = Response(data, 200, mimetype='application/zip', as_attachment=True, attachment_filename="archive.zip")

    # remove temp_path
    #rmtree(temp_path)    
    return Response("OK", 200)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default=80, type=int)
    args = parser.parse_args()
    app.run(host='0.0.0.0', port=args.port)
  

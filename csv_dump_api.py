
import argparse
from io import StringIO

from flask import Flask, request, Response

from csv_dump import get_tables, write_table_output
from query_info import QueryInfo
from utils import get_config


app = Flask(__name__)
config = get_config() 

@app.route('/csvdata/<table>', methods = ['POST'])
def csv_dump(table):
  response = None

  if request.method == 'POST':
    params = request.get_json()

    # Check params
    field_check = all(field in params for field in ["start_ts", "end_ts", "type", "name"])
    size_check = len(params.items()) == 4

    if not field_check or not size_check:
      response = Response("Bad Request", 400)
    elif table not in get_tables():
      response = Response("No Such Table: " + table, 404)
    else:
      query = None
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
      """ TODO: This is gross; I'd prefer to stream but that's been difficult:
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

  return response
 
if __name__ == '__main__':
  parser = argparse.ArgumentParser()
  parser.add_argument("--port", default=80, type=int)
  args = parser.parse_args()
  app.run(host='0.0.0.0', port=args.port)
  

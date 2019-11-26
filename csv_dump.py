import psycopg2
import os
import errno
import logging
import json
import argparse
from datetime import datetime
from query_info import QueryInfo
from utils import initialize_logging, get_config, get_connection

def get_tables(cur):
    ''' Gets all tables from a connected database.

    Args:
        cur (psycopg2.cursor): Cursor to execute queries to the connected database.

    Returns:
        tables: List of names(str) of the tables within the databse
    '''
    logging.info("Retrieving tables from database.")
    query = "SELECT table_name FROM information_schema.tables WHERE table_schema='public'"
    cur.execute(query)
    tables = [item[0] for item in cur.fetchall()]
    logging.debug("Tables retrieved: {}".format(tables))
    return tables

def check_directory(dir_path):
    '''Checks to see if the given directory path exists. If it does not, it creates the path.
    
    Args:
        dir_path (str): directory path to be checked for existance, or to be created.
    '''
    # If directory does not exist, create it
    if not os.path.exists(os.path.dirname(dir_path)):
        logging.info("Directory does not exist: {}. Creating directory.".format(dir_path))
        try: # Avoid Race condition (Case: directory being created at the same time as this.)
            os.makedirs(os.path.dirname(dir_path))
            logging.info("Directory created: {}".format(dir_path))
        except OSError as e:
            if e.errno != errno.EEXIST:
                logging.exception("Directory could not be created: {}".format(dir_path))
            else:
                logging.info("File Path Exists: {}".format(dir_path))

def write_table_output(cur, table_query_info, fp):
    table_name = table_query_info.table_name
    table_query = table_query_info.sql_query
    create_temp_table = table_query_info.create_temp_table
    if create_temp_table:
        cur.execute(table_query)
        # fetch from temp table
        query = "select * from {}_temp".format(table_name)
    else:
        query = table_query
    copy_query = "COPY ({}) TO STDOUT  DELIMITER ',' CSV HEADER;".format(query)
    cur.copy_expert(copy_query, fp)

def query_and_write_data(cur, table_query_info, base_path, file_prefix):
    '''Queries all data and headers from a given table, and writes it to a csv file.
    Path of the file is as such: {base_path}/{start_date_end_date_table_name}.csv

    Args:
        cur (psycopg2.cursor): Cursor to execute queries to the connected database
        table_query_info (str): Each table query info has table name, table query, params flag and temp_table flag
        base_path (str): Base path of where the CSV file dump of the table is to be stored.
                        (Example: /example/path/to/desired/directory/)
        start_date: start endpoint where when the VM was active
        end_date:  end endpoint where the VM was active
    '''
    table_name = table_query_info.table_name
    file_path = "{}/{}.csv".format(base_path, file_prefix + "_" + table_name)
    check_directory(file_path)
    logging.info("Dumping {} table to {}".format(table_name, file_path))
    with open(file_path, "w+") as file_to_write:
        write_table_output(cur, table_query_info, file_to_write)
    logging.info("{} table contents successfully written to {}\n".format(table_name, file_path))

def parse_program_execution_args():
    # check for args
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='filter_type', required=True)

    # Filtering arguments are start_timestamp and end_timestamp
    timeframe_parser = subparsers.add_parser('timeframe')
    timeframe_parser.add_argument("--start_timestamp",
                                  help="the start timestamp where a VM was active",
                                  required=True)
    timeframe_parser.add_argument("--end_timestamp",
                                  help="the end timestamp till when a VM was active",
                                  required=True)

    # Filtering arguments are project_id, start_timestamp and end_timestamp
    project_parser = subparsers.add_parser('project')
    project_parser.add_argument("--project_id", help="the project id to filter the data", required=True)
    project_parser.add_argument("--start_timestamp",
                                help="the start timestamp where a VM was active",
                                required=True)
    project_parser.add_argument("--end_timestamp",
                                help="the end timestamp till when a VM was active",
                                required=True)

    # Filtering arguments are institution_id, start_timestamp and end_timestamp
    institution_parser = subparsers.add_parser('institution')
    institution_parser.add_argument("--institution_id", help="the institution id to filter the data", required=True)
    institution_parser.add_argument("--start_timestamp",
                                    help="the start timestamp where a VM was active",
                                    required=True)
    institution_parser.add_argument("--end_timestamp",
                                    help="the end timestamp till when a VM was active",
                                    required=True)
    args = parser.parse_args()

    # Filter based arguments in command line
    file_prefix, table_query_infos = None, None
    if args.filter_type == 'timeframe':
        start_date = args.start_timestamp
        end_date = args.end_timestamp
        file_prefix = start_date + "_" + end_date
        table_query_infos = QueryInfo.get_query_infos_by_timeframe(start_date, end_date)
    elif args.filter_type == 'project':
        project_id = args.project_id
        start_date = args.start_timestamp
        end_date = args.end_timestamp
        file_prefix = project_id + start_date + "_" + end_date
        table_query_infos = QueryInfo.get_query_infos_by_project(project_id, start_date, end_date)
    elif args.filter_type == 'institution':
        institution_id = args.institution_id
        start_date = args.start_timestamp
        end_date = args.end_timestamp
        file_prefix = institution_id + start_date + "_" + end_date
        table_query_infos = QueryInfo.get_query_infos_by_institution(institution_id, start_date, end_date)
    else:
        print("Invalid filtering types")

    return file_prefix, table_query_infos


if __name__ == '__main__':
    # Initialize Logging
    initialize_logging()
    # Get DB Configs
    config = get_config()
    # Establish Connection to Database
    conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    cur = conn.cursor()
    # Dump CSV files
    base_path = "{}/moc_reporting_csv_dump/{}".format(os.getcwd(), datetime.now().strftime("%m_%d_%Y_%H:%M:%S"))

    file_prefix, table_query_infos = parse_program_execution_args()
    for table_query_info in table_query_infos:
        query_and_write_data(cur, table_query_info, base_path, file_prefix)
    # Close connection
    conn.close()



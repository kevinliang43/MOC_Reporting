import psycopg2
import os
import errno
import logging
import json
import argparse
import configparser
from datetime import datetime
from query_info import QueryInfo

def initialize_logging():
    '''Initializes Logging'''
    log_format = "%(asctime)s [%(levelname)s]: %(filename)s(%(funcName)s:%(lineno)s) >> %(message)s"
    logging.basicConfig(format=log_format, level=logging.INFO)
    logging.info("Initialized Logging.")

def get_config(filepath='config.json', section='database'):
    """ Reads config file and retrieves configs from a given section

    Args:
        filepath (str): Filepath of the config file.
        section (str): Secton of the config file to read

    Return:
        kwargs (dict): dictionary of config key:value pairs.
    """
    with open(filepath) as json_config:
        config = json.load(json_config)
    try:
        return config[section]
    except:
        raise Exception('Please check the formatting of your {} config file'.format(filepath))

def get_connection(host, dbname, user, password):
    ''' Attempts to establish a connection to a given Database

    Args:
        host(str): Host to connect to
        dbname (str): Name of the Database
        user (str): Name of the User
        password (str): Password
    Returns:
        conn: Connection object to the given database.
        
    '''
    try:
        logging.info("Connecting to {} at {} as {}".format(dbname, host, user))
        conn = psycopg2.connect(host=host, dbname=dbname, user=user, password=password)
        logging.info("Connection to Database established.")
        return conn
    except Exception as e:
        logging.exception("Could not establish connection to database.")
        

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

def query_and_write_data(cur, table_query_info, base_path, start_date, end_date):
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
    table_query = table_query_info.sql_query
    need_params = table_query_info.params_required
    create_temp_table = table_query_info.create_temp_table
    if create_temp_table:
        if need_params:
            args = start_date, end_date
            cur.execute(table_query, args)
        else:
            cur.execute(table_query)
        # fetch from temp table
        query = "select * from {}_temp".format(table_name)
    else:
        if need_params:
            query = table_query.format(start_date, end_date)
        else:
            query = table_query
    file_path = "{}/{}.csv".format(base_path, start_date + "_" + end_date + "_" + table_name)
    check_directory(file_path)
    logging.info("Dumping {} table to {}".format(table_name, file_path))
    with open(file_path, "w+") as file_to_write:  # TODO: Should we write if the file already exists?
        copy_query = "COPY ({}) TO STDOUT  DELIMITER ',' CSV HEADER;".format(query)
        cur.copy_expert(copy_query, file_to_write)
        logging.info("{} table contents successfully written to {}\n".format(table_name, file_path))


if __name__ == '__main__':

    # check for args
    parser = argparse.ArgumentParser()
    parser.add_argument("--active_timestamp", nargs='+', help="the timestamps where a VM was active", type=str)
    args = parser.parse_args()
    start_date = args.active_timestamp[0]
    end_date = args.active_timestamp[1]

    # Initialize Logging
    initialize_logging()
    # Get DB Configs
    config = get_config()
    # Establish Connection to Database
    conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    cur = conn.cursor()
    # Dump CSV files
    base_path = "{}/moc_reporting_csv_dump/{}".format(os.getcwd(), datetime.now().strftime("%m_%d_%Y_%H:%M:%S"))
    for table_query_info in QueryInfo.get_query_infos_by_timeframe():
        query_and_write_data(cur, table_query_info, base_path, start_date, end_date)
    # Close connection
    conn.close()



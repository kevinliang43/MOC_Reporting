import psycopg2
import os
import errno
import logging
<<<<<<< HEAD
import json
=======
import argparse
import configparser
>>>>>>> add args for filtering
from datetime import date

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
    Path of the file is as such: {base_path}{table_name}/{todays date}.csv

    Args:
        cur (psycopg2.cursor): Cursor to execute queries to the connected database
        table_name (str): Name of the table to query
        base_path (str): Base path of where the CSV file dump of the table is to be stored.
                        (Example: /example/path/to/desired/directory/)
    '''
    table_name, table_query, need_params, create_temp_table = table_query_info
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
    #file_path = "{}{}/{}.csv".format(base_path, table_name, date.today().strftime("%Y_%m_%d"))
    file_path = "{}/{}/{}.csv".format(base_path, date.today().strftime("%Y_%m_%d"), start_date + "_" + end_date + "_" + table_name)
    check_directory(file_path)
    logging.info("Dumping {} table to {}".format(table_name, file_path))
    with open(file_path, "w+") as file_to_write:  # TODO: Should we write if the file already exists?
        copy_query = "COPY ({}) TO STDOUT  DELIMITER ',' CSV HEADER;".format(query)
        cur.copy_expert(copy_query, file_to_write)
        logging.info("{} table contents successfully written to {}\n".format(table_name, file_path))


def get_tables_and_query_mapping():
    # Each element is of the format (table_name, sql_query, params_required, temp_table_created)
    tables_and_query = []
    tables_and_query.append(('item_ts', "select * from item_ts where start_ts between '{}' and '{}'", True, False))
    tables_and_query.append(('item', 'create temp table item_temp as (select * from item i where exists (select 1 from item_ts it where it.domain_id = i.domain_id and it.project_id = i.project_id and it.item_id = i.item_id and it.item_type_id = i.item_type_id and it.start_ts between %s and %s))', True, True))
    tables_and_query.append(('item_type', 'select * from item_type where item_type_id in (select item_type_id from item_temp)', False, False ))
    tables_and_query.append(('catalog_item', 'select * from catalog_item where item_type_id in (select item_type_id from item_temp)', False, False))
    tables_and_query.append(('project', 'create temp table project_temp as (select distinct p.* from project p inner join item_temp i on p.domain_id = i.domain_id and p.project_id = i.project_id)', False, True))
    tables_and_query.append(('domain', 'select * from domain where domain_id in (select domain_id from project_temp)', False, False))
    tables_and_query.append(('institution2project', 'create temp table institution2project_temp as (select * from institution2project i2p where exists (select 1 from project_temp p where p.project_id = i2p.project_id and p.domain_id = i2p.domain_id))', False, True))
    tables_and_query.append(('institution', 'select * from institution where institution_id in (select institution_id from institution2project_temp)', False, False))
    tables_and_query.append(('project2poc', 'create temp table project2poc_temp as (select distinct p2p.* from project2poc p2p inner join project_temp p on p2p.domain_id = p.domain_id and p2p.project_id = p.project_id)', False, True))
    tables_and_query.append(('poc', 'select * from poc where poc_id in (select poc_id from project2poc_temp)', False, False))
    tables_and_query.append(('address', 'select * from address where address_id in (select address_id from poc inner join project2poc_temp p on poc.poc_id = p.poc_id)', False, False))
    return tables_and_query

if __name__ == '__main__':
<<<<<<< HEAD
=======

    config = configparser.ConfigParser()
    config.read('config.ini')
    db_name = config['DatabaseSection']['database.dbname']
    user = config['DatabaseSection']['database.user']

    # check for args
    parser = argparse.ArgumentParser()
    parser.add_argument("--active_timestamp", nargs='+', help="the timestamps where a VM was active", type=str)
    args = parser.parse_args()
    start_date = args.active_timestamp[0]
    end_date = args.active_timestamp[1]

>>>>>>> add args for filtering
    # Initialize Logging
    initialize_logging()
    # Get DB Configs
    config = get_config()
    # Establish Connection to Database
    conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    cur = conn.cursor()
    # Dump CSV files
    base_path = "{}/moc_reporting_csv_dump/".format(os.getcwd())
    for table_query_info in get_tables_and_query_mapping():
        query_and_write_data(cur, table_query_info, base_path, start_date, end_date)
    # Close connection
    conn.close()



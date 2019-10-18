import psycopg2
import os
import errno
import logging
from datetime import date
from configparser import ConfigParser

def initialize_logging():
    '''Initializes Logging'''
    log_format = "%(asctime)s [%(levelname)s]: %(filename)s(%(funcName)s:%(lineno)s) >> %(message)s"
    logging.basicConfig(format=log_format, level=logging.INFO)
    logging.info("Initialized Logging.")

def get_config(filepath='database.ini', section='postgresql'):
    """ Reads config file and retrieves configs from a given section
    
    Args:
        filepath (str): Filepath of the config file.
        section (str): Secton of the config file to read

    Return:
        kwargs (dict): dictionary of config key:value pairs.
    """
    # Initialize the parser 
    parser = ConfigParser()
    parser.read(filepath)

    config = {}
    if parser.has_section(section):
        params = parser.items(section)
        for param in params:
            config[param[0]] = param[1]
    else:
        raise Exception('Please check your {} config file.'.format(filepath))
    return config


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

def query_and_write_data(cur, table_name, base_path):
    '''Queries all data and headers from a given table, and writes it to a csv file.
    Path of the file is as such: {base_path}{table_name}/{todays date}.csv

    Args:
        cur (psycopg2.cursor): Cursor to execute queries to the connected database
        table_name (str): Name of the table to query
        base_path (str): Base path of where the CSV file dump of the table is to be stored.
                        (Example: /example/path/to/desired/directory/)
    '''
    query = "COPY (SELECT * FROM {}) TO STDOUT  DELIMITER ',' CSV HEADER;".format(table_name)
    file_path = "{}{}/{}.csv".format(base_path, table_name, date.today().strftime("%Y_%m_%d"))
    check_directory(file_path)
    logging.info("Dumping {} table to {}".format(table_name, file_path))
    with open(file_path, "w+") as file_to_write: #TODO: Should we write if the file already exists?
        cur.copy_expert(query, file_to_write)
        logging.info("{} table contents successfully written to {}\n".format(table_name, file_path))
    

if __name__ == '__main__':
    # Initialize Logging
    initialize_logging()
    # Get DB Configs
    config = get_config() 
    # Establish Connection to Database
    conn = get_connection(**config)
    cur = conn.cursor()
    # Dump CSV files
    base_path = "{}/moc_reporting_csv_dump/".format(os.getcwd())
    for table in get_tables(cur):
        query_and_write_data(cur, table, base_path) 
    # Close connection
    conn.close()



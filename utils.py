import psycopg2
import logging
import json

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
        


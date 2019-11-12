from utils import get_connection, get_config
import petl as etl

def get_connection_to_dbs():
    '''
    Migrates the data from DB to a different DB
    '''

    from_db_conn = get_connection('localhost', 'postgres', 'anju', '')
    config = get_config()
    to_db_conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    return from_db_conn, to_db_conn

def table_to_table_mapper():
    table_mapper = []
    table_mapper.append({'institution': 'institution'})
    table_mapper.append({'poc': 'poc'})
    table_mapper.append({'institution2poc': 'institution2poc'})
    table_mapper.append({'domain': 'service'})
    table_mapper.append({'institution2project': 'institution2moc_project'})
    table_mapper.append({})

def transfer_data(from_db_conn, to_db_conn):
    '''
    Transfer data from databases given cursor to execute queries to connected databases
    :param from_db_conn: cursor to From database
    :param to_db_conn: cursor to To database
    :return:
    '''

    fk_dep_tables = ['poc']
    for table_name in fk_dep_tables:
        table = etl.fromdb(to_db_conn, "select * from {} where 1=0".format(table_name))
        etl.todb(table, to_db_conn, table_name)

    insert_as_tables = ['institution', 'address', 'item_type', 'item2item', 'catalog_item']
    for table_name in insert_as_tables:
        table = etl.fromdb(from_db_conn, "select * from {}".format(table_name))
        etl.todb(table, to_db_conn, table_name)

    # inserting dummy address for constraint matching
    dummy_address = [{'address_id': -1}]
    dummy_address_table = etl.fromdicts(dummy_address)
    etl.appenddb(dummy_address_table, to_db_conn, 'address')

    poc = etl.fromdb(from_db_conn, 'select * from poc')
    poc_transformed = etl.cutout(poc, 'domain_id', 'user_uid')
    poc_dummy_address = etl.replace(poc_transformed, 'address_id', None, -1)
    etl.todb(poc_dummy_address, to_db_conn, 'poc')

    #institution2poc = etl.fromdb(from_db_conn, 'select * from institution2poc')
    #inst2poc_transformed = etl.rename(institution2poc, 'poc_role_id', 'role_id')
    #etl.todb(inst2poc_transformed, to_db_conn, 'institution2poc')

    #role = etl.fromdb(from_db_conn, 'select * from poc_role')
    #role_transformed = etl.rename(role, {'poc_role_id': 'role_id', 'poc_role_name': 'role_name',
    #                                     'poc_role_desc': 'role_description',
    #                                     'poc_role_type': 'role_level'})
    #etl.todb(role_transformed, to_db_conn, 'role')



if __name__ == '__main__':

    from_db, to_db = get_connection_to_dbs()
    transfer_data(from_db, to_db)














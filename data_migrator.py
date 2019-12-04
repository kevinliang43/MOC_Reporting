from utils import get_connection, get_config
import petl as etl

def get_connection_to_dbs(source_config):
    '''
    Get the connection to the source and destination databases
    :param: configs to connect to source DB
    '''
    from_db_conn = get_connection(source_config['host'], source_config['dbname'],
                                  source_config['user'], source_config['pass'])
    config = get_config()
    to_db_conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    return from_db_conn, to_db_conn

def transfer_data(from_db_conn, to_db_conn):
    '''
    Transfer data from databases given cursor to execute queries to connected databases
    Limitations:
    1. poc.address_id is currently marked as  -1 since it was not provided in test data and is a FK non-null constraint
    2. institution2poc table is not available in old schema
    3. role table is already populated in bill.sql file so that table is skipped by this script
    4. poc_poc_id is currently set to be poc_id since no relevant information is available about the column
    5. project2moc_project.role_id column is not available in old schema and is a not null field in new schema
        so we default it to 1 for now.
    6. project2moc_project.username is not available from old schema so currently set to empty
    7. raw_item_ts.item_id has duplicates when imported from item_ts. So we currently filter out and insert only uniques.

    :param from_db_conn: source database connection
    :param to_db_conn: destination database connection
    '''

    # Emptying out tables with possible foreign key constraint issues
    fk_dep_tables = ['poc2project', 'poc2moc_project', 'poc', 'raw_item_ts', 'item', 'project', 'institution2moc_project' ]
    for table_name in fk_dep_tables:
        table = etl.fromdb(to_db_conn, "select * from {} where 1=0".format(table_name))
        etl.todb(table, to_db_conn, table_name)

    # Tables with no change in schema
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

    project_names_table = etl.fromdb(from_db_conn, "select distinct project_name from project")
    moc_project_transformed = etl.addrownumbers(project_names_table)
    moc_project_transformed = etl.rename(moc_project_transformed, {'row': 'moc_project_id'})
    etl.todb(moc_project_transformed, to_db_conn, 'moc_project')

    domain = etl.fromdb(from_db_conn, "select * from domain")
    domain_table_transformed = etl.cutout(domain, 'domain_uid')
    domain_table_transformed = etl.rename(domain_table_transformed, {'domain_id': 'service_id', 'domain_name': 'service_name'})
    etl.todb(domain_table_transformed, to_db_conn, 'service')

    project = etl.fromdb(from_db_conn, "select * from project")
    moc_project = etl.fromdb(to_db_conn, "select * from moc_project")
    project_moc_project_joined = etl.join(project, moc_project, key='project_name')
    project_table_transformed = etl.cutout(project_moc_project_joined, 'project_name')
    project_table_transformed = etl.rename(project_table_transformed, {'domain_id': 'service_id', 'project_uid': 'project_uuid'})
    etl.todb(project_table_transformed, to_db_conn, 'project')

    institution2project = etl.fromdb(from_db_conn, "Select * from institution2project")
    project = etl.fromdb(to_db_conn, "select project_id, moc_project_id from project")
    inst2project_project_joined = etl.join(institution2project, project, key='project_id')
    inst2moc_project = etl.cutout(inst2project_project_joined, 'domain_id')
    etl.todb(inst2moc_project, to_db_conn, 'institution2moc_project')

    project2poc = etl.fromdb(from_db_conn, "select * from project2poc")
    project2poc_project_joined = etl.join(project2poc, project, key='project_id')
    poc2moc_project = etl.cutout(project2poc_project_joined, 'project_id', 'domain_id')
    poc2moc_project = etl.addfield(poc2moc_project, 'role_id', 1)
    poc2moc_project = etl.addfield(poc2moc_project, 'poc_poc_id', lambda rec: rec['poc_id'])
    etl.todb(poc2moc_project, to_db_conn, 'poc2moc_project')

    poc2project = etl.cutout(project2poc, 'domain_id')
    poc2project = etl.addfield(poc2project, 'role_id', 1)
    poc2project = etl.addfield(poc2project, 'username', '')
    etl.todb(poc2project,to_db_conn, 'poc2project')

    item = etl.fromdb(from_db_conn, "select * from item")
    item_transformed = etl.cutout(item, 'domain_id')
    etl.todb(item_transformed, to_db_conn, 'item')

    raw_item_ts_unique = etl.fromdb(from_db_conn, "WITH summary AS ( SELECT its.item_id, its.start_ts, its.end_ts, its.state, its.catalog_item_id, ROW_NUMBER() OVER(PARTITION BY its.item_id) AS rk FROM ITEM_TS its) SELECT s.* FROM summary s WHERE s.rk = 1")
    raw_item_ts_unique = etl.cutout(raw_item_ts_unique, 'rk')
    etl.todb(raw_item_ts_unique, to_db_conn, 'raw_item_ts')


if __name__ == '__main__':

    # Source DB is the DB from which you have to migrate data which is based on the old schema model.
    # The data in the source_db will be migrated to the moc_reporting DB. Provide the source_db configs below.
    source_db_config = {"dbname":"", "host":"", "user": "", "pass": ""}
    from_db, to_db = get_connection_to_dbs(source_db_config)
    transfer_data(from_db, to_db)

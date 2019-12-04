class QueryInfo:
    def __init__(self, table_name, sql_query, params_required, create_temp_table):
        self.table_name = table_name
        self.sql_query = sql_query
        self.params_required = params_required
        self.create_temp_table = create_temp_table

    @staticmethod
    def get_query_infos_by_project(project_id, start_date, end_date):
        '''
        Gets an array of queries to get the data from each table. Starts with the project_id in project table
        :return: an array of queries for fetching data in each tables.
        '''
        query_infos = []
        query_infos.append(QueryInfo('project','create temp table project_temp as (select * from project where project_id = {})'.format(project_id), True, True))
        query_infos.append(QueryInfo('moc_project','create temp table moc_project_temp as (select * from moc_project where moc_project_id in (select moc_project_id from project_temp))',False, True))
        query_infos.append(QueryInfo('institution2moc_project','create temp table institution2moc_project_temp as (select * from institution2moc_project where project_id in (select project_id from project_temp) and moc_project_id in (select moc_project_id from moc_project_temp))',False, True))
        query_infos.append(QueryInfo('institution','select * from institution where institution_id in (select institution_id from institution2moc_project _temp)',False, False))
        query_infos.append(QueryInfo('poc2institution','create temp table poc2institution_temp as (select * from poc2institution where institution_id in (select institution_id from institution2moc_project_temp))',False, True))
        query_infos.append(QueryInfo('poc','create temp table poc_temp as (select * from poc where poc_id in (select poc_id from poc2institution_temp))',False, True))
        query_infos.append(QueryInfo('address','select * from address where address_id in (Select address_id from poc where poc_id in (select poc_id from poc2institution_temp))',False, False))
        query_infos.append(QueryInfo('role', 'select * from role where role_id in (select role_id from poc2institution_temp)', False,False))
        query_infos.append(QueryInfo('poc2moc_project','select * from poc2moc_project where poc_id in (select poc_id from poc_temp) and moc_project_id in (select moc_project_id from moc_project_temp)',False, False))
        query_infos.append(QueryInfo('poc2project','select * from poc2project where project_id in (select project_id from project_temp) and poc_id in (select poc_id from poc_temp)',False, False))
        query_infos.append(QueryInfo('service','create temp table service_temp as (select * from service where service_id in (select service_id from project_temp))',False, True))
        query_infos.append(QueryInfo('hardware_inventory','select * from hardware_inventory where service_id in (select service_id from service_temp)',False, False))
        query_infos.append(QueryInfo('item','create temp table item_temp as (select * from item where project_id in (select project_id from project_temp))',False, True))
        query_infos.append(QueryInfo('item2item', 'select * from item2item where primary_item in (select item_id from item_temp)',False, False))
        query_infos.append(QueryInfo('item_type','create temp table item_type_temp as (select * from item_type where item_type_id in (select item_type_id from item_temp))',False, True))
        query_infos.append(QueryInfo('catalog_item','select * from catalog_item where item_type_id in (select item_type_id from item_type_temp)',False, False))
        query_infos.append(QueryInfo('raw_item_ts',"select * from raw_item_ts where item_id in (select item_id from item_temp) and start_ts between '{}' and '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('summarized_item_ts',"select * from summarized_item_ts where item_id in (select item_id from item_temp) and start_ts>='{}' and end_ts <= '{}'".format(start_date, end_date), True, False))
        return query_infos

    @staticmethod
    def get_query_infos_by_institution(institution_id, start_date, end_date):
        '''
        Gets an array of queries to get the data from each table. Uses institution_id, start_date and end_date parameters
        to filter the data
        :return: an array of queries for fetching data in each tables.
        '''
        query_infos = []
        query_infos.append(QueryInfo('institution', 'create temp table institution_temp as (select * from institution where institution_id = {})'.format(institution_id), True, True))
        query_infos.append(QueryInfo('institution2moc_project', 'create temp table institution2moc_project_temp as (select * from institution2moc_project where institution_id = {})'.format(institution_id), True, True))
        query_infos.append(QueryInfo('moc_project', 'create temp table moc_project_temp as (select * from moc_project where moc_project_id in (select moc_project_id from institution2moc_project_temp))', False, True))
        query_infos.append(QueryInfo('project', 'create temp table project_temp as (select * from project where project_id in (select project_id from institution2moc_project_temp))', False, True))
        query_infos.append(QueryInfo('service', 'create temp table service_temp as (select * from service where service_id in (select service_id from project_temp))', False, True))
        query_infos.append(QueryInfo('hardware_inventory', 'select * from hardware_inventory where service_id in (select service_id from service_temp)', False, False))
        query_infos.append(QueryInfo('item', 'create temp table item_temp as (select * from item where project_id in (select project_id from project_temp))', False, True))
        query_infos.append(QueryInfo('item2item', 'select * from item2item where primary_item in (select item_id from item_temp)', False, False))
        query_infos.append(QueryInfo('item_type', 'create temp table item_type_temp as (select * from item_type where item_type_id in (select item_type_id from item_temp))', False, True))
        query_infos.append(QueryInfo('catalog_item', 'select * from catalog_item where item_type_id in (select item_type_id from item_type_temp)', False, False))
        query_infos.append(QueryInfo('raw_item_ts', "select * from raw_item_ts where item_id in (select item_id from item_temp) and start_ts between '{}' and '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('summarized_item_ts',"select * from summarized_item_ts where item_id in (select item_id from item_temp) and start_ts>='{}' and end_ts <= '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('poc2institution', 'create temp table poc2institution_temp as (select * from poc2institution where institution_id = {})'.format(institution_id), True, True ))
        query_infos.append(QueryInfo('poc','create temp table poc_temp as (select * from poc where poc_id in (select poc_id from poc2institution_temp))', False, True))
        query_infos.append(QueryInfo('address','select * from address where address_id in (Select address_id from poc where poc_id in (select poc_id from poc2institution_temp))', False, False))
        query_infos.append(QueryInfo('role', 'select * from role where role_id in (select role_id from poc2institution_temp)', False, False))
        query_infos.append(QueryInfo('poc2project', 'select * from poc2project where project_id in (select project_id from project_temp) and poc_id in (select poc_id from poc_temp)', False, False))
        query_infos.append(QueryInfo('poc2moc_project', 'select * from poc2moc_project where poc_id in (select poc_id from poc_temp) and moc_project_id in (select moc_project_id from moc_project_temp)', False, False))
        return query_infos

    @staticmethod
    def get_query_infos_by_timeframe(start_date, end_date):
        '''
        Gets an array of queries to get the data from each table. Starts with the timestamp in item_ts table
        :return: an array of queries for fetching data in each tables.
        '''
        # Each element is of the format (table_name, sql_query, params_required, temp_table_created)
        query_infos = []
        query_infos.append(QueryInfo('raw_item_ts', "select * from raw_item_ts where start_ts between '{}' and '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('summarized_item_ts', "select * from summarized_item_ts where start_ts >= '{}' and end_ts <= '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('item', "create temp table item_temp as (select * from item where item_id in (select item_id from raw_item_ts where start_ts between '{}' and '{}'))".format(start_date, end_date), True, True))
        query_infos.append(QueryInfo('item_type','create temp table item_type_temp as (select * from item_type where item_type_id in (select item_type_id from item_temp))', False, True))
        query_infos.append(QueryInfo('item2item', 'select * from item2item where primary_item in (select item_id from item_temp)', False, False))
        query_infos.append(QueryInfo('catalog_item', 'select * from catalog_item where item_type_id in (select item_type_id from item_type_temp)', False, False))
        query_infos.append(QueryInfo('project', 'create temp table project_temp as (select * from project where project_id in (select project_id from item_temp))', False, True))
        query_infos.append(QueryInfo('moc_project', 'create temp table moc_project_temp as (select * from moc_project where moc_project_id in (select moc_project_id from project_temp))', False, True))
        query_infos.append(QueryInfo('institution2moc_project', 'create temp table institution2moc_project_temp as (select * from institution2moc_project where project_id in (select project_id from project_temp) and moc_project_id in (select moc_project_id from moc_project_temp))', False, True))
        query_infos.append(QueryInfo('institution', 'select * from institution where institution_id in (select institution_id from institution2moc_project_temp)', False, False))
        query_infos.append(QueryInfo('poc2institution', 'create temp table poc2institution_temp as (select * from poc2institution where institution_id in (select institution_id from institution2moc_project_temp))', False, True))
        query_infos.append(QueryInfo('poc', 'create temp table poc_temp as (select * from poc where poc_id in (select poc_id from poc2institution_temp))', False, True))
        query_infos.append(QueryInfo('address', 'select * from address where address_id in (Select address_id from poc where poc_id in (select poc_id from poc2institution_temp))', False, False))
        query_infos.append(QueryInfo('role', 'select * from role where role_id in (select role_id from poc2institution_temp)', False, False))
        query_infos.append(QueryInfo('poc2moc_project', 'select * from poc2moc_project where poc_id in (select poc_id from poc_temp) and moc_project_id in (select moc_project_id from moc_project_temp)', False, False))
        query_infos.append(QueryInfo('poc2project', 'select * from poc2project where project_id in (select project_id from project_temp) and poc_id in (select poc_id from poc_temp)', False, False))
        query_infos.append(QueryInfo('service', 'create temp table service_temp as (select * from service where service_id in (select service_id from project_temp))', False, True))
        query_infos.append(QueryInfo('hardware_inventory', 'select * from hardware_inventory where service_id in (select service_id from service_temp)', False, False))
        return query_infos








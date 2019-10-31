class QueryInfo:
    def __init__(self, table_name, sql_query, params_required, create_temp_table):
        self.table_name = table_name
        self.sql_query = sql_query
        self.params_required = params_required
        self.create_temp_table = create_temp_table

    @staticmethod
    def get_query_infos_by_timeframe(start_date, end_date):
        '''
        Gets an array of queries to get the data from each table. Starts with the timestamp in item_ts table
        :return: an array of queries for fetching data in each tables.
        '''
        # Each element is of the format (table_name, sql_query, params_required, temp_table_created)
        query_infos = []
        query_infos.append(QueryInfo('item_ts', "select * from item_ts where start_ts between '{}' and '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('item', "create temp table item_temp as (select * from item i where exists (select 1 from item_ts it where it.domain_id = i.domain_id and it.project_id = i.project_id and it.item_id = i.item_id and it.item_type_id = i.item_type_id and it.start_ts between '{}' and '{}'))".format(start_date, end_date), True, True))
        query_infos.append(QueryInfo('item_type', 'select * from item_type where item_type_id in (select item_type_id from item_temp)', False, False ))
        query_infos.append(QueryInfo('catalog_item', 'select * from catalog_item where item_type_id in (select item_type_id from item_temp)', False, False))
        query_infos.append(QueryInfo('project', 'create temp table project_temp as (select distinct p.* from project p inner join item_temp i on p.domain_id = i.domain_id and p.project_id = i.project_id)', False, True))
        query_infos.append(QueryInfo('domain', 'select * from domain where domain_id in (select domain_id from project_temp)', False, False))
        query_infos.append(QueryInfo('institution2project', 'create temp table institution2project_temp as (select * from institution2project i2p where exists (select 1 from project_temp p where p.project_id = i2p.project_id and p.domain_id = i2p.domain_id))', False, True))
        query_infos.append(QueryInfo('institution', 'select * from institution where institution_id in (select institution_id from institution2project_temp)', False, False))
        query_infos.append(QueryInfo('project2poc', 'create temp table project2poc_temp as (select distinct p2p.* from project2poc p2p inner join project_temp p on p2p.domain_id = p.domain_id and p2p.project_id = p.project_id)', False, True))
        query_infos.append(QueryInfo('poc', 'select * from poc where poc_id in (select poc_id from project2poc_temp)', False, False))
        query_infos.append(QueryInfo('address', 'select * from address where address_id in (select address_id from poc inner join project2poc_temp p on poc.poc_id = p.poc_id)', False, False))
        return query_infos

    @staticmethod
    def get_query_infos_by_project(project_id, start_date, end_date):
        '''
        Gets an array of queries to get the data from each table. Starts with the project_id in project table
        :return: an array of queries for fetching data in each tables.
        '''
        query_infos = []
        query_infos.append(QueryInfo('project', 'create temp table project_temp as (select * from project where project_id = {})'.format(project_id), True, True))
        query_infos.append(QueryInfo('moc_project', 'create temp table moc_project_temp as (select * from moc_project where moc_project_id in (select moc_project_id from project_temp))', False, True))
        query_infos.append(QueryInfo('institution2moc','create temp table institution2moc_project _temp as (select * from institution2moc_project where project_id in (select project_id from project_temp) and moc_project id in (select moc_project_id from moc_project_temp)', False, True))
        query_infos.append(QueryInfo('institution', 'select * from institution where institution_id in (select institution_id from in institution2moc_project _temp)', False, False))
        query_infos.append(QueryInfo('institution2poc', 'create temp table institution2poc _temp as (select * from institution2poc where institution_id in (select institution_id from in institution2moc_project _temp));', False, True))
        query_infos.append(QueryInfo('poc', 'create temp table poc_temp as (select * from poc where poc_id in (select poc_id from institution2poc _project _temp))', False, True))
        query_infos.append(QueryInfo('address', 'select * from address where address_id in (Select address_id from poc where poc_id in (select poc_id from institution2poc _temp))', False, False))
        query_infos.append(QueryInfo('role', 'select * from role where role_id in (select role_id from institution2poc _temp)', False, False))
        query_infos.append(QueryInfo('poc2moc_project', 'select * from poc2moc_project where poc_id in (select poc_id in poc_temp) and moc_project_id in (select moc_project_id in moc_pproject_temp)', False, False))
        query_infos.append(QueryInfo('poc2project', 'select * from poc2project where project_id in (select project_id from project_temp) and poc_id in (select poc_id in poc_temp)', False, False))
        query_infos.append(QueryInfo('service', 'create temp table service_temp as (select * from service where service_id in (select service_id from project_temp)', False, True))
        query_infos.append(QueryInfo('hardware_inventory', 'select * from hardware_inventory where service id in (select service_id from service_temp)', False, False))
        query_infos.append(QueryInfo('item', 'create temp table item_temp as (select * from item where project_id in (select project_id from project_temp))', False, True))
        query_infos.append(QueryInfo('item2item', 'select * from item2item where primary_item in (select item_id from item_temp)', False, False))
        query_infos.append(QueryInfo('item_type', 'create temp table item_type_temp as (select * from item_type where item_type_id in (select item_type_id from item_temp))', False, True))
        query_infos.append(QueryInfo('catalog_item', 'select * from catalog_item where item_type_id in (select item_type_id in item_type_temp)', False, False))
        query_infos.append(QueryInfo('raw_item_ts', "select * from raw_item_ts where item_id in item_temp and start_ts between '{}' and '{}'".format(start_date, end_date), True, False))
        query_infos.append(QueryInfo('summarized_item_ts', "select * from summerized_item_ts where item_id in item_temp and start_ts between '{}' and '{}'".format(start_date, end_date), True, False))




class QueryInfo:
    def __init__(self, table_name, sql_query, params_required, create_temp_table):
        self.table_name = table_name
        self.sql_query = sql_query
        self.params_required = params_required
        self.create_temp_table = create_temp_table

    @staticmethod
    def get_query_infos_by_timeframe():
        '''
        Gets an array of queries to get the data from each table. Starts with the timestamp in item_ts table
        :return: an array of queries for fetching data in each tables.
        '''
        # Each element is of the format (table_name, sql_query, params_required, temp_table_created)
        query_infos = []
        query_infos.append(QueryInfo('item_ts', "select * from item_ts where start_ts between '{}' and '{}'", True, False))
        query_infos.append(QueryInfo('item', 'create temp table item_temp as (select * from item i where exists (select 1 from item_ts it where it.domain_id = i.domain_id and it.project_id = i.project_id and it.item_id = i.item_id and it.item_type_id = i.item_type_id and it.start_ts between %s and %s))', True, True))
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

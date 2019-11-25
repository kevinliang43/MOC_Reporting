#!/usr/bin/env python

import logging
import argparse
import psycopg2
import sys
from dateutil.relativedelta import relativedelta
from utils import initialize_logging, get_config, get_connection
from datetime import datetime, timedelta


def time_delta(end_time, start_time):
    """
        Calculates the total seconds between two datetime objects

        Args:
            end_time (datetime.datetime): End time
            start_time (datetime.datetime): Start time
  
        Return:
            total time (int) between the end and start time in seconds.
    """
    return (end_time - start_time).total_seconds()

def calculate_end_date(start_date, period):

    """ Calcualtes the end_date, given a start_date and a time period from the start date
        
        Args: 
            start_date (str): Start Date (Format: YYYY-MM-DD)
            period (str): Period to increment (day, week, month)
        Return:
            end_date (str): End Date of the (Format: YYYY-MM-DD)
    """
    period_mapping = {"day": timedelta(days=1), "week":timedelta(days=7), "month": relativedelta(months=1)}

    # Calculate End Date
    start_date_fmt = datetime.strptime(start_date, "%Y-%m-%d")
    end_date_fmt = start_date_fmt + period_mapping[period]
    end_date = datetime.strftime(end_date_fmt, "%Y-%m-%d") # Bring End Date back into str

    return end_date

def execute_query(cur, query, return_rows):
    """ Executes a given query to a database pointed to by a given cursor
        
        Args:
            cur: cursor pointing to the connected database
            query (str): String representing the query to execute
            return_rows(bool): True if there are any rows to be returned from the query. False otherwise

        Returns:
            Response (List of rows) from the query
            empty list if return_rows = False
    """
    
    try:
        cur.execute(query)
        results = []
        if return_rows:
            results = cur.fetchall()
        return results
    except psycopg2.Error as e:
        logging.error(e)

def query_item_ts(cur, start_date, end_date, item_id):
    """Queries all rows from raw_item_ts with the given item_id, start_date, and period
        Args:
        cur: Cursor to the connected database
        start_date (str): Start Date of the summary period (Format: YYYY-MM-DD)
        period (str): Period of the summary rollup (day, week, month)
        item_id (str): ID of the item to create a summary roll up for
    """
    
    # Format Query, Order by start_ts ASCENDING 
    query = "SELECT * FROM raw_item_ts WHERE item_id={} AND start_ts>='{}' AND end_ts<'{}' ORDER BY start_ts ASC;".format(item_id, start_date, end_date)
   
    # Log Query
    logging.info("Querying usage data for ID: {} from {} to {}".format(item_id, start_date, end_date))

    # Execute Query and retrieve usage data
    usage_data = execute_query(cur, query, True)
    return usage_data

def aggregate_summary(usage_data):
    """ Aggregates list of usage data into {state: total_time}
    
        Args:
        usage_data: Sorted List (by start_ts) of usage data tuples [(item_id, catalog_item_id, state, start_ts, end_ts), ...]

        Return:
        dictionary mapping each state to the total time spent in that state for the given period of time
    """
    # Initialize aggregate_summary mapping
    agg_summary = {}

    if len(usage_data) > 0:
        # Add Time for first element in the row
        cur_id, cur_cat_id, cur_state, cur_start, cur_end = usage_data[0]
        agg_summary[cur_state] = time_delta(cur_end, cur_start) 

        # Iterate through rest of the usage data rows
        for row in usage_data[1:]:
            # Get the next row info
            next_id, next_cat_id, next_state, next_start, next_end = row
            
            # Case 1: Next state is the same as the current state
            if cur_state == next_state:
                agg_summary[next_state]+= time_delta(next_end, cur_end)
            
            # Case 2: Next state is not the same as the current state
            else:
                if next_state in agg_summary: # Mapping exists, add time
                    agg_summary[next_state] += time_delta(next_end, next_start)
                else: # Mapping does not exist
                    agg_summary[next_state] = time_delta(next_end, next_start)
            
            # Update current row info
            cur_id, cur_cat_id, cur_state, cur_start, cur_end = row
    
    return agg_summary

def write_summary(cur, agg_summary, period, start_date, end_date, item_id, catalog_item_id):
    """
        Writes the contents of a given aggregated summary dictionary
        to the summarized_item_ts

        Args:
            cur: cursor pointing to the connected database
            agg_summary (dict): aggregated summary mapping {state(str): time in state (int seconds)}
            period (str): period of aggregation (day, week, month)
            start_date (str): Start date of Summary Period in the form (YYYY-MM-DD)
            end_date (str): End date of Summary Period in the form (YYYY-MM-DD)
            item_id (str): ID of item that is being summarized
            catalog_item_id (str): Catalog ID of the item
    
        Returns:
            1 for successful write
            0 for unsuccessful write
    """
 
    query = """INSERT INTO summarized_item_ts (item_id, start_ts, catalog_item_id, state, end_ts, summary_period, state_time) VALUES({},'{}',{},'{}','{}','{}',{});"""

    # Write each item in aggregate summary
    for state, time in agg_summary.items():
        # Log query being executed 
        logging.info("Inserting summary for ID: {} for state: {} from {} to {}".format(item_id, state, start_date, end_date))
        # Execute query
        f_query = query.format(item_id, start_date, catalog_item_id, state, end_date, period, time)
        if execute_query(cur, f_query, False) is None:
            return 0 # Query execution failed. Abort
    return 1 # Success


if __name__ == '__main__':

    # Check Args
    parser = argparse.ArgumentParser()
    parser.add_argument("--start_date", help="Start date of summary rollup (In the form of YYYY-MM-DD).", required=True)
    parser.add_argument("--period", choices=['day', 'week', 'month'], help="Summary Period (day, week, month).", required=True)
    parser.add_argument("--item_id", help="ID of item to create summary rollup for.", required=True)
    args = parser.parse_args()
    
    # Args
    start_date = args.start_date
    period = args.period
    item_id = args.item_id
    
    # Initialize Logging
    initialize_logging()
    
    # Calculate End Date
    # A period of 'month' requires a start date that is the first of a given month
    end_date = calculate_end_date(start_date, period)

    # Get DB Configs
    config = get_config()
    # Establish Connection to Database
    conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    cur = conn.cursor()

    # Query raw_item_ts 
    raw_item_ts_rows = query_item_ts(cur, start_date, end_date, item_id)
    # Check if we are able to summarize
    if raw_item_ts_rows and len(raw_item_ts_rows) > 0:
        catalog_item_id = raw_item_ts_rows[0][1]

        # Aggregate
        agg_summary = aggregate_summary(raw_item_ts_rows)

        # Write to summarized_item_ts
        write_success = write_summary(cur, agg_summary, period, start_date, end_date, item_id, catalog_item_id)

        # If successfully written all rows, commit.
        if write_success:
            conn.commit()
        else:
            logging.error("Error in writing summary rows. Please check inputs.")
    else:
        logging.error("No rows found for the given parameters: (item_id: {}, start_date: {}, period: {})".format(item_id, start_date, period))

    # Close
    logging.info("Closing Connection to {}".format(config['dbname']))
    cur.close() 
    conn.close()

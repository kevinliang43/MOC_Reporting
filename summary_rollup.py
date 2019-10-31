#!/usr/bin/env python

import logging
import argparse
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
    period_mapping = {"day":1, "week":7} #TODO: Include Month
    
    # Calculate End Date
    start_date_fmt = datetime.strptime(start_date, "%Y-%m-%d")
    end_date_fmt = start_date_fmt + timedelta(days=period_mapping[period])
    end_date = datetime.strftime(end_date_fmt, "%Y-%m-%d") # Bring End Date back into str

    return end_date

def summarized_item_ts_max_id(cur):
    """ Gets the highest ID from summarized_item_ts

        Args:
            cur: cursor pointing to connected database
    """
    # Retrieve Max ID
    query = "SELECT item_id FROM summarized_item_ts ORDER BY item_id DESC LIMIT 1"
    cur.execute(query)
    results = cur.fetchall()
    if len(results) > 0:
        return results[0][0]
    else:
        return 0


def query_item_ts(cur, start_date, end_date, catalog_item_id):
    """Queries all rows from raw_item_ts with the given item_id, start_date, and period
        Args:
        cur: Cursor to the connected database
        start_date (str): Start Date of the summary period (Format: YYYY-MM-DD)
        period (str): Period of the summary rollup (day, week, month)
        catalog_item_id (str): ID of the item to create a summary roll up for
    """
    
    # Format Query, Order by start_ts ASCENDING 
    query = "SELECT * FROM raw_item_ts WHERE catalog_item_id={} AND start_ts>='{}' AND end_ts<'{}' ORDER BY start_ts ASC;".format(catalog_item_id, start_date, end_date)
   
    # Log Query
    logging.info("Querying usage data for ID: {} from {} to {}".format(catalog_item_id, start_date, end_date))

    # Execute Query
    cur.execute(query)

    # Retrieve Usage Data
    usage_data = cur.fetchall()
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

def write_summary(cur, agg_summary, period, start_date, end_date, catalog_item_id):
    """
        Writes the contents of a given aggregated summary dictionary
        to the summarized_item_ts

        Args:
            cur: cursor pointing to the connected database
            agg_summary (dict): aggregated summary mapping {state(str): time in state (int seconds)}
            period (str): period of aggregation (day, week, month)
            start_date (str): Start date of Summary Period in the form (YYYY-MM-DD)
            end_date (str): End date of Summary Period in the form (YYYY-MM-DD)
            catalog_item_id (str): ID of item that is being summarized
    """
    query = """INSERT INTO summarized_item_ts (item_id, start_ts, catalog_item_id, state, end_ts, summary_period, state_time) VALUES({},'{}',{},'{}','{}','{}',{});"""
    cur_id = summarized_item_ts_max_id(cur) + 1

    for state, time in agg_summary.items():
        logging.info("Inserting summary for ID: {} for state: {} from {} to {}".format(catalog_item_id, state, start_date, end_date))
        cur.execute(query.format(cur_id, start_date, catalog_item_id, state, end_date, period, time))
        cur_id += 1



if __name__ == '__main__':

    # Check Args
    parser = argparse.ArgumentParser()
    parser.add_argument("--start_date", help="Start date of summary rollup (In the form of YYYY-MM-DD).", required=True)
    parser.add_argument("--period", choices=['day', 'week', 'month'], help="Summary Period (day, week, month).", required=True)
    parser.add_argument("--catalog_item_id", help="ID of item to create summary rollup for.", required=True)
    args = parser.parse_args()
    
    # Args
    start_date = args.start_date
    period = args.period
    catalog_item_id = args.catalog_item_id
    end_date = calculate_end_date(start_date, period)

    # Initialize Logging
    initialize_logging()
    # Get DB Configs
    config = get_config()
    # Establish Connection to Database
    conn = get_connection(config['host'], config['dbname'], config['user'], config['pass'])
    cur = conn.cursor()

    # Query raw_item_ts 
    raw_item_ts_rows = query_item_ts(cur, start_date, end_date, catalog_item_id)

    # Aggregate
    agg_summary = aggregate_summary(raw_item_ts_rows)

    print(summarized_item_ts_max_id(cur))
    # Write to summarized_item_ts
    write_summary(cur, agg_summary, period, start_date, end_date, catalog_item_id)

    # Commit
    conn.commit()

    # Close
    logging.info("Closing Connection to {}".format(config['dbname']))
    cur.close() 
    conn.close()

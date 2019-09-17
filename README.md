
MOC Reporting
=============

## Goal

The ultimate goal of the MOC Reporting project is to generate actionable
business objects in the form of summary usage reports. The system must be able
to generate these reports across the axes of Institution, Project, and User.


## Users and Personas

Three Primary Groups are relevant for discussing the goals of the project. The
following definitions will be used throughout this document and repository:
 - MOC Administrators: technical personnel at the MOC who are responsible for
   MOC operations and generating MOC billing and usage reports
 - Partner Administrators: Persons-of-Contact at MOC partner corporations
   and institutions who are responsible for the partner's investment in and
   participation with the MOC
 - Partner Users: researchers and engineers who use the MOC in their day-to-day
   tasks

The project will begin with MOC Administrators (Rob) who need to produce
usage reports for the partner institutions. The project is anticipated to expand
to other users, however, those users' personas are not yet well defined.


## Scope

At the highest level, the system must be able to tally the total usage for every
Virtual Machine at the MOC. Further, the system must be able to aggregate that
data across three major segments:
 1. Projects
 2. Institutions
 3. Users

Each pair of segments has the following cardinality:
 - Project-Institution: Many-to-Many
 - Project-User: Many-to-Many
 - User-Institution: Many-to-One


"Projects" refers to collections of MOC Service instances. Each Project defines 
an area of control and will have one User that is responsbile for that Project. 
Further, Projects are a recursive data type: sub-projects can be defined on a 
given project, and reports generated for that projct must include appropriately
labeled usage data for all sub-projects. The project tree will be rooted in a 
node that represents the whole of the MOC. Lastly, a notion of relative buy-in /
investment will need to be defined for all projects with multiple funding 
Institutions.

The system will automatically gather data from MOC Service Provider Systems and
begin a processing pipeline. The pipeline will build an intermediary store of
usage data from which reports and dump files can be generated. The generated
usage data will be persistent. Length of persistency shall be defined at
run-time by the MOC Administrator.

The system will be able to produce reports accurate to one hour. The system may
be extend to provide finer reporting capabilities. Reports generated must be
consistent with the raw data collected from OpenStack. The system must run
automated consistency verification routines against all data source streams.

The system must support the following front-ends for data export:
 - CSV File, a Dump of all usage data over a given time period
 - PDF File, a Human-Readable Report

A complete billing system with graphical front-end is considered beyond the
scope of this project, however defining a model for pricing will be attempted if
time allows. 


## Features

1. MOC Usage data collector
    - Will poll MOC services to get machine usage data
2. Data pipeline
    - Will process raw MOC Service Provider data into the intermediary usage
      data format
    - Pipeline will produce data consistent with MOC logs
    - Multiple Pipeline Architectures must be supported
3. A database that houses processed usage data
4. "Front-end" server for accessing processed data
    - Provides Interface point for user utilities for generating reports
5. CSV Database dump utility
    - Will write all entries in the usage database over a specified time period
      to downloadable files
    - Allows checking of consistency with MOC Logs
6. Basic Monthly Aggregate Usage Report Generator
    - Will extend current work that produces elementary reports


## Solution Concept
#### Global Overview

The system can conceptually be understood has consisting of three major layers:
 1. MOC Service Provider Systems
 2. The Data Collection Engine
 3. "Front-End" Consumers

Layer 1 consists of the "real services" on the MOC that are responsible for
providing the MOC's Virtualization Services. OpenStack is the keystone element
here. Layer 2 will be implemented during the course of this project. It will be
responsible for using the interfaces provided by the services in Layer 1 to
aggregate data and providing an API to the Layer 3 services. Proof-of-Concept
demonstration applications at Layer 3 will be developed to showcase the ability
of the Layer 2 aggregation system.


#### Design Implications and Discussion
##### Todo


## Acceptance criteria
 1. The system must be able to both generate a human readable report and dump a
    CSV database of usage data
##### Todo

## Open Questions
 - What is the minimum necessary level of usage data granularity
    - What minimum level of granularity is needed internally to provide this, if
      different?
 - How often will the pipeline need to run?
 - Guidelines/Expectations for outputted report?


## General comments
#### Todo

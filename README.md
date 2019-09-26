
Massachusetts Open Cloud (MOC) Reporting
=============

## Goal

The ultimate goal of the MOC Reporting project (MOC Reporting System)
is to generate actionable business objects in the form of summary usage reports.
These reports will summarize just OpenStack usage for now. The system must be able to generate these reports across the axes of Institution, Project, and User.
Furthermore, the system must also be able to generate intermediate CSV artifacts
that act as a snapshot of the database holding all usage information being collected
from OpenStack. CSV dumps will be created for all object and relationship tables
for a user-specified time period.


## Stretch Goals
Although the current goal of the project revolves around generating reports for just OpenStack, if time permits, we will extend functionality of the MOC Reporting System
so that the system will be able to collect data from and generate CSV files and reports
for Zabbix, Openshift, and Ceph.


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
an area of control and will have one User that is responsible for that Project.
Further, Projects are a recursive data type: sub-projects can be defined on a
given project, and reports generated for that project must include appropriately
labeled usage data for all sub-projects. The project tree will be rooted in a
node that represents the whole of the MOC. Lastly, a notion of relative buy-in /
investment will need to be defined for all projects with multiple funding
Institutions.

The system created will automatically gather data from OpenStack
and build an intermediary store of
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

If time permits and the initial Scope of the project has been satisfied and completed,
We can extend this project to collect data from and produce reports for
Openshift, Ceph, and Zabbix services, again across the three major segments.


## Features

1. OpenStack Usage data collector
    - Data that will be collected include:
     - [User](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-user)
     - [Flavors](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-flavor)
     - [Router](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-router)
     - [Neutron Information](https://docs.openstack.org/mitaka/install-guide-obs/common/get_started_networking.html)
       - [Networks](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-network)
       - [Subnets](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-subnet)
       - [Floating IPs](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-floating-ip-address)
     - [Instances](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-instance)
     - [Volumes from Cinder](https://docs.openstack.org/mitaka/install-guide-obs/common/glossary.html#term-volume)
     - [Panko Data](https://docs.openstack.org/panko/latest/webapi/index.html)
     [Insert Entity Relationship Diagram Here When Ready]
    - Data collected will be stored in a PostgreSQL database (TODO: Add ER Diagram when available)
    - Data collection scripts will be run every 15 minutes
    - Python 3 or Perl Scripts

2. database
    - Contains raw data from OpenStack
    - Contains tables for Institutions, Users, and Projects
    - Database is auditable (READ actions only performed)
    - PostgreSQL RDBMS

3. Data pipeline
    - Extracts raw OpenStack usage data from PostgreSQL database.
    - Processes raw data into CSV files
      - Each CSV file containing all entries from a user-specified time period.
      - Each CSV file is mapped to a single table within the database.
    - Pipeline will produce data consistent with MOC logs
    - Pipeline will be automated to run every day.
    - CSV Files will be stored on MOC servers and will be persistent
    - Can only perform READ actions on the database containing raw OpenStack data.
4. "Front-end" server for accessing processed data
    - Provides Interface point for user utilities for generating reports
5. CSV Database dump utility
    - Will write all entries in the usage database over a specified time period
      to downloadable files
    - Allows checking of consistency with MOC Logs
6. Basic Monthly Aggregate Usage Report Generator
    - Will extend current work that produces elementary reports
7. Hardware/VM Specs:
  - OpenStack x86 VMs
  - TBD



## Solution Concept
#### Global Overview

The system can conceptually be understood has consisting of three major layers:
 1. MOC Service Provider Systems
 2. The Data Collection Engine
 3. "Front-End" Consumers

<img src="/images/architechture_diagram.png" width="750" height="500">

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
 1. The system must be able to both generate a human readable report
    summarizing OpenStack usage and dump across Institutions, Projects, and Users.
 2. The system creates intermediate CSV files that represent the state of the
    database tables from a current period of time and be stored on MOC servers.
 3. Data collection, storing into databases, and saved as CSV files will be automated.

##### Todo

## Open Questions
 - What is the minimum necessary level of usage data granularity
    - What minimum level of granularity is needed internally to provide this, if
      different?
 - How often will the pipeline need to run?
 - Guidelines/Expectations for outputted report?
 - What are the hardware specs of the machines to be running this system?
 - Containerization: What software is necessary in containers to run scripts?
 - Definition of Production level


## General comments
#### Todo


MOC Reporting
=============

## Goals

The utlimate goal of the MOC Reporting project is to build usage monitoring 
functionality into the MOC and a basic analytics system to leverage the data 
produced by the monitoring system. The current expectation is that the project 
will be focused on instrumenting MOC systems to provide the appropriate hooks 
for a data collection system and implementing that collection system. 


## Users and Personas

Three Primary Groups are relevant for discussion the goals of the project. The
following definitions will be used throughout this document:
 - MOC Administrators: technical personel at the MOC who are responsible for 
   MOC operations and generating MOC billing and usage reports
 - Partner Administrators: Persons-of-Contact at MOC partner corporations 
   and institutions who are responsible for the partner's investment in and 
   participation with the MOC
 - Partner Users: researchers and engineers who use the MOC in their day-to-day
   tasks

The project will begin by targeting MOC Administrators (Rob) who need to produce
usage reports for the partner institutions. The project is anticipated to expand
to other users. However, those users' personas are not yet well defined. 


## Scope

At the highest level, the system must be able to tally the total usage for every
Partner User at the MOC. Further, the system must be able to aggregate that data
across two major segments: 
 1. Project
 2. Institution
 
Conceptually, the two segements can be considered orthagonal with multiple 
Institutions participating in/funding any given project. In such a case, a 
notion of relative buy-in/investment would need to be defined for all 
participating Instiutions (for a given Project). The well-scoped-ness of such a 
condition is under consideration. Further, a complete billing system with 
graphical front-end are considered beyond the scope of this project. 


## Features
#### Todo


## Solution Concept
#### Global Overview

The system can conceptually be understood has consisting of three major layers:
 1. MOC Service Provider Systems
 2. The Data Collection Engine
 3. "Front-End" Consumers

Layer 1 consists of the "real services" on the MOC that are responsible for 
providing the MOC's Virtualization Services. OpenStack is the keystone element 
here. Layer 2 will be impelmented during the course of this project. It will be
responsible for using the interfaces provided by the services in Layer 1 to 
aggregate data and providing an API to the Layer 3 services. Proof-of-Concept 
demonstration applications at Layer 3 will be developed to showcase the ability 
of the Layer 2 aggregation system. 


#### Design Implications and Discussion
##### Todo


## Acceptance criteria
##### Todo


## Open Questions
 - What is the minimum level of accuracy 
    - What minimum level of accuracy is needed internally to provide this, if 
      different?
 - $ Project \elementof \over{?} Institution $
    - Or, can $ Project \intesect i \neq \emptyset \for \exists \not \unique i \isa Institution $


## General comments
#### Todo

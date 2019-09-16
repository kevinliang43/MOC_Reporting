
create database moc_billing;
\connect moc_billing
drop table if exists address cascade;
drop table if exists poc_role cascade;
drop table if exists poc cascade;
drop table if exists institution cascade;
drop table if exists domain cascade;
drop table if exists project cascade;
drop table if exists institution2project cascade;
drop table if exists institution2poc cascade;
drop table if exists project2poc cascade;
drop table if exists item_type cascade;
drop table if exists item cascade;
drop table if exists item2item;
drop table if exists catalog_item cascade;
drop table if exists item_ts cascade;

create table address ( 
    address_id bigserial primary key,        -- id for a given address
    line1 varchar(150),                      -- line 1 of an address [10th Floor Gates Pavilion]
    line2 varchar(150),                       -- line 2 of an address [3400 Spruce street]
    city varchar(150),                       -- city name            [philadelphia]
    state varchar(50),                       -- state name           [PA]
    postal_code varchar(40),                 -- postal code          [19104]
    country varchar(100) );                  -- Country              [USA]

create table domain (                 -- This is a administrative notion for describing where the resource (VM, container, ... ) is located
    domain_id bigserial primary key, 
    domain_uid varchar(500),          -- unique id for the domain (if exists) in OpenStack, this is the domain UUID
    domain_name varchar(200) );       -- name for the domain [MOC_Engage1, MOC_Kaizen, e1-openshift, openshift ... ]

create table poc (                                      -- this defines who get the report attn: [first_name] [last_name]
    poc_id bigserial primary key,                       -- point of contact id
    domain_id integer references domain(domain_id),
    address_id integer references address(address_id),  -- address id see address table
    Last_name varchar(100),                             -- poc's last name
    first_name varchar(100),                            -- poc's first name  
    username varchar(200),                              -- poc's username
    user_uid varchar(200),
    email varchar(200),
    phone varchar(20)
    );     

create table institution (                   
    institution_id bigserial primary key,      --
    institution_name varchar(200) );           -- name of the institution [MOC, Boston University Harvard, RedHat]

create table project ( 
    domain_id integer references domain(domain_id), 
    project_id bigserial,                           
    project_uid varchar(500),                       -- unique id for the project (if exists) in OpenStack, this is the project UUID
    project_name varchar(200),                      -- name for the project
    primary key (domain_id,project_id) );

create table institution2project(                                  -- mapping table to map institutions to projects
    institution_id integer references institution(institution_id), 
    domain_id integer,
    project_id integer,
    percent_owned integer,                                         -- the percentage owned in thousandths of a percent
    foreign key(domain_id,project_id) references project(domain_id,project_id),
    primary key(institution_id,domain_id,project_id) );

create table poc_role(
    poc_role_id bigserial primary key,
    poc_role_type integer,
    poc_role_name varchar(200),
    poc_role_desc varchar(500)
    );    

insert into poc_role (poc_role_name, poc_role_type,  poc_role_desc)  values
  ('Lead', 1, 'Project lead role'),
  ('Member', 2, 'Project member');

create table institution2poc(                                        -- mapping table to map institutions to points of contacts
    poc_id integer references poc(poc_id),                    
    institution_id integer references institution(institution_id),
    poc_role_id integer );

create table project2poc(                                                         --  mapping table to map projects to points of contaces
    poc_id integer references poc(poc_id), 
    domain_id integer,
    project_id integer,
    role integer,
    foreign key(domain_id, project_id) references project(domain_id, project_id),
    primary key(poc_id,domain_id,project_id) );

create table item_type(                      -- Basic item description
    item_type_id bigserial primary key,      
    item_definition varchar(50),             -- A short unique description [ VM(8,32,10),VOL(500G), OBJ(500G) ]
    item_desc varchar(500) );                -- A easy to read description [ vertual machine with 8 vCPUs, 32 Gigs Memory, 10 Gig drive. ]

create table item ( 
    domain_id integer,
    project_id integer, 
    item_name varchar(150),
    item_uid varchar(150),
    item_id bigserial, 
    item_type_id integer references item_type(item_type_id),                      -- the item being used in the project
    foreign key(domain_id, project_id) references project(domain_id, project_id), 
    primary key(domain_id, project_id, item_id, item_type_id)
    );

create table item2item(
    primary_item integer,             -- sort of a parent item  router -> network -> sub_net -> VM -> (volume, floating ip, ... )
    secondary_item integer );

create table catalog_item (                                   -- This associates a price with an item at a starting time
    catalog_item_id bigserial,
    item_type_id integer references item_type(item_type_id),
    create_ts timestamp,                                      -- When this price becomes effective for the associated item
    price integer,                                            -- The price of the item in to thousands of a dollar per hour
    primary key (catalog_item_id),
    unique (catalog_item_id, item_type_id, create_ts) );

create table item_ts(                  -- this keeps tract of how much of a catalog item that the end user uses
    domain_id integer,
    project_id integer, 
    item_type_id integer,
    item_id integer, 
    start_ts timestamp,                -- the starting timestamp for using the item
    end_ts timestamp,                  -- the ending tiemstamp for using the item
    state varchar(50),                 -- the state of the vm
    size real,                         -- the size (in GB) for disks and object stores
    catalog_item_id integer references catalog_item(catalog_item_id),  --the catalog item to assocate the description of price for the item (per hour)
    item_size real,
    foreign key (domain_id, project_id, item_type_id, item_id) references item(domain_id, project_id, item_type_id, item_id)
    );


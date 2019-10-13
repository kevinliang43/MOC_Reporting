/*  In postgres, before running first create the database by running:

    > CREATE DATABASE moc_reporting;

    then run:

    > psql --username=postgres moc_reporting < bill.sql
    
    TODO:  Clean up this install procedure
*/

drop table if exists address cascade;
drop table if exists role cascade;
drop table if exists poc cascade;
drop table if exists institution cascade;
drop table if exists service cascade;
drop table if exists moc_project cascade;
drop table if exists project cascade;
drop table if exists institution2moc_project cascade;
drop table if exists poc2institution cascade;
drop table if exists poc2project cascade;
drop table if exists poc2moc_project cascade;
drop table if exists item_type cascade;
drop table if exists item cascade;
drop table if exists item2item;
drop table if exists catalog_item cascade;
drop table if exists raw_item_ts cascade;
drop table if exists summerized_item_ts cascade;
drop table if exists hardware_inventory cascade;


CREATE SEQUENCE role_role_id_seq_2;
CREATE TABLE role (
                role_id BIGINT NOT NULL DEFAULT nextval('role_role_id_seq_2'),
                role_name VARCHAR(100) DEFAULT 'viewer' NOT NULL,
                role_description VARCHAR(300) DEFAULT 'Viewer priveleges' NOT NULL,
                role_level INTEGER NOT NULL,
                CONSTRAINT role_pk PRIMARY KEY (role_id)
);

/* COMMENT ON COLUMN role.role_level IS 'This is to indicate:
    1 -> institution role
    2 -> moc_project role
    3 -> project role';
*/

/* institution */
INSERT INTO role (role_name, role_description, role_level) values ('Sr. Software Engineer', '', 1);
INSERT INTO role (role_name, role_description, role_level) values ('Bustiness Administrator', '', 1);

/* moc_project */
INSERT INTO role (role_name, role_description, role_level) values ('admin', 'Billing Authority', 2);
INSERT INTO role (role_name, role_description, role_level) values ('admin', 'Principle Investigator', 2);
INSERT INTO role (role_name, role_description, role_level) values ('member', '', 2);

/* project */
INSERT INTO role (role_name, role_description, role_level) values ('admin', '', 3);
INSERT INTO role (role_name, role_description, role_level) values ('member', '', 3);
INSERT INTO role (role_name, role_description, role_level) values ('viewer', '', 3);

ALTER SEQUENCE role_role_id_seq_2 OWNED BY role.role_id;
CREATE SEQUENCE service_service_id_seq_1;
CREATE TABLE service (
                service_id BIGINT NOT NULL DEFAULT nextval('service_service_id_seq_1'),
                service_name VARCHAR(100) NOT NULL,
                CONSTRAINT service_pk PRIMARY KEY (service_id)
);


ALTER SEQUENCE service_service_id_seq_1 OWNED BY service.service_id;
CREATE SEQUENCE hardware_inventory_hardware_inventory_id_seq;
CREATE TABLE hardware_inventory (
                hardware_inventory_id VARCHAR NOT NULL DEFAULT nextval('hardware_inventory_hardware_inventory_id_seq'),
                service_id BIGINT NOT NULL,
                manufacturer VARCHAR(250) NOT NULL,
                model VARCHAR(250) NOT NULL,
                serial_number VARCHAR(250) NOT NULL,
                type VARCHAR(200) NOT NULL,
                CONSTRAINT hardware_inventory_pk PRIMARY KEY (hardware_inventory_id)
);


ALTER SEQUENCE hardware_inventory_hardware_inventory_id_seq OWNED BY hardware_inventory.hardware_inventory_id;
CREATE SEQUENCE moc_project_moc_project_id_seq_1;
CREATE TABLE moc_project (
                moc_project_id BIGINT NOT NULL DEFAULT nextval('moc_project_moc_project_id_seq_1'),
                project_name VARCHAR(200),
                CONSTRAINT moc_project_pk PRIMARY KEY (moc_project_id)
);


ALTER SEQUENCE moc_project_moc_project_id_seq_1 OWNED BY moc_project.moc_project_id;
CREATE SEQUENCE project_project_id_seq;
CREATE TABLE project (
                project_id BIGINT NOT NULL DEFAULT nextval('project_project_id_seq'),
                moc_project_id BIGINT NOT NULL,
                service_id BIGINT NOT NULL,
                project_uuid VARCHAR(250),
                CONSTRAINT project_pk PRIMARY KEY (project_id)
);


ALTER SEQUENCE project_project_id_seq OWNED BY project.project_id;
CREATE TABLE address (
                address_id BIGINT NOT NULL,
                line1 VARCHAR(150),
                line2 VARCHAR(15),
                city VARCHAR(150),
                state VARCHAR(50),
                postal_code VARCHAR(40),
                country VARCHAR(100),
                CONSTRAINT address_pk PRIMARY KEY (address_id)
);


CREATE TABLE institution (
                institution_id BIGINT NOT NULL,
                institution_name VARCHAR(200),
                CONSTRAINT institution_pk PRIMARY KEY (institution_id)
);


CREATE TABLE institution2moc_project (
                project_id INTEGER NOT NULL,
                institution_id BIGINT NOT NULL,
                moc_project_id BIGINT NOT NULL,
                percent_owned INTEGER,
                CONSTRAINT institution2moc_project_pk PRIMARY KEY (project_id, institution_id, moc_project_id)
);


CREATE TABLE poc (
                poc_id BIGINT NOT NULL,
                last_name VARCHAR(100),
                first_name VARCHAR(100),
                username VARCHAR(200),
                email VARCHAR(200),
                phone VARCHAR(20),
                address_id BIGINT NOT NULL,
                CONSTRAINT poc_pk PRIMARY KEY (poc_id)
);


CREATE TABLE poc2project (
                project_id BIGINT NOT NULL,
                poc_id BIGINT NOT NULL,
                role_id BIGINT NOT NULL,
                username VARCHAR(250) NOT NULL,
                service_uuid VARCHAR(250),
                CONSTRAINT poc2project_pk PRIMARY KEY (project_id, poc_id)
);


CREATE TABLE poc2moc_project (
                poc_id INTEGER NOT NULL,
                moc_project_id BIGINT NOT NULL,
                poc_poc_id BIGINT NOT NULL,
                role_id BIGINT NOT NULL,
                username VARCHAR(200),
                CONSTRAINT poc2moc_project_pk PRIMARY KEY (poc_id, moc_project_id, poc_poc_id)
);


CREATE TABLE poc2institution (
                poc_id BIGINT NOT NULL,
                institution_id BIGINT NOT NULL,
                role_id BIGINT NOT NULL,
                CONSTRAINT poc2institution_pk PRIMARY KEY (poc_id, institution_id)
);


CREATE TABLE item_type (
                item_type_id BIGINT NOT NULL,
                item_definition VARCHAR(50),
                item_desc VARCHAR(500),
                CONSTRAINT item_type_pk PRIMARY KEY (item_type_id)
);


CREATE TABLE catalog_item (
                catalog_item_id BIGINT NOT NULL,
                item_type_id BIGINT NOT NULL,
                create_ts TIMESTAMP,
                price INTEGER,
                CONSTRAINT catalog_item_pk PRIMARY KEY (catalog_item_id)
);


CREATE SEQUENCE item_item_id_seq;
CREATE TABLE item (
                item_id BIGINT NOT NULL DEFAULT nextval('item_item_id_seq'),
                project_id BIGINT NOT NULL,
                item_name VARCHAR(150),
                item_uid VARCHAR(150),
                item_type_id BIGINT NOT NULL,
                CONSTRAINT item_pk PRIMARY KEY (item_id)
);


ALTER SEQUENCE item_item_id_seq OWNED BY item.item_id;
CREATE TABLE item2item (
                primary_item BIGINT NOT NULL,
                secondary_item BIGINT NOT NULL,
                CONSTRAINT item2item_pk PRIMARY KEY (primary_item, secondary_item)
);


CREATE TABLE raw_item_ts (
                item_id BIGINT NOT NULL,
                catalog_item_id INTEGER,
                state VARCHAR(50),
                start_ts TIMESTAMP,
                end_ts TIMESTAMP,
                CONSTRAINT raw_item_ts_pk PRIMARY KEY (item_id)
);


CREATE TABLE summerized_item_ts (
                item_id BIGINT NOT NULL,
                start_ts TIMESTAMP NOT NULL,
                catalog_item_id INTEGER NOT NULL,
                state VARCHAR(50) NOT NULL,
                end_ts TIMESTAMP NOT NULL,
                summary_period INTEGER NOT NULL,
                CONSTRAINT summerized_item_ts_pk PRIMARY KEY (item_id)
);

/* 
COMMENT ON COLUMN summerized_item_ts.summary_period IS 'Summary periods:

1 -> daily
2 -> weekly
3 -> monthly';
*/

ALTER TABLE poc2moc_project ADD CONSTRAINT role_poc2moc_project_fk
FOREIGN KEY (role_id)
REFERENCES role (role_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2institution ADD CONSTRAINT role_poc2institution_fk
FOREIGN KEY (role_id)
REFERENCES role (role_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2project ADD CONSTRAINT poc2project_role_fk
FOREIGN KEY (role_id)
REFERENCES role (role_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE project ADD CONSTRAINT service_project_fk
FOREIGN KEY (service_id)
REFERENCES service (service_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE hardware_inventory ADD CONSTRAINT service_hardware_inventory_fk
FOREIGN KEY (service_id)
REFERENCES service (service_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE institution2moc_project ADD CONSTRAINT project_institution2moc_project_fk
FOREIGN KEY (moc_project_id)
REFERENCES moc_project (moc_project_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE project ADD CONSTRAINT moc_project_service_fk
FOREIGN KEY (moc_project_id)
REFERENCES moc_project (moc_project_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2moc_project ADD CONSTRAINT moc_project_poc2moc_project_fk
FOREIGN KEY (moc_project_id)
REFERENCES moc_project (moc_project_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE item ADD CONSTRAINT provisioned_service_item_fk
FOREIGN KEY (project_id)
REFERENCES project (project_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2project ADD CONSTRAINT project_poc2project_fk
FOREIGN KEY (project_id)
REFERENCES project (project_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc ADD CONSTRAINT address_poc_fk
FOREIGN KEY (address_id)
REFERENCES address (address_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2institution ADD CONSTRAINT institution_poc2institution_fk
FOREIGN KEY (institution_id)
REFERENCES institution (institution_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE institution2moc_project ADD CONSTRAINT institution_institution2moc_project_fk
FOREIGN KEY (institution_id)
REFERENCES institution (institution_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2institution ADD CONSTRAINT poc_poc2institution_fk
FOREIGN KEY (poc_id)
REFERENCES poc (poc_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2moc_project ADD CONSTRAINT poc_poc2moc_project_fk
FOREIGN KEY (poc_poc_id)
REFERENCES poc (poc_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE poc2project ADD CONSTRAINT poc_poc2project_fk
FOREIGN KEY (poc_id)
REFERENCES poc (poc_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE item ADD CONSTRAINT item_type_item_fk
FOREIGN KEY (item_type_id)
REFERENCES item_type (item_type_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE catalog_item ADD CONSTRAINT item_type_catalog_item_fk
FOREIGN KEY (item_type_id)
REFERENCES item_type (item_type_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE raw_item_ts ADD CONSTRAINT item_item_ts_fk
FOREIGN KEY (item_id)
REFERENCES item (item_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE item2item ADD CONSTRAINT item_item2item_fk
FOREIGN KEY (primary_item)
REFERENCES item (item_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE item2item ADD CONSTRAINT item_item2item_fk1
FOREIGN KEY (secondary_item)
REFERENCES item (item_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

ALTER TABLE summerized_item_ts ADD CONSTRAINT raw_item_ts_summerized_item_ts_fk
FOREIGN KEY (item_id)
REFERENCES raw_item_ts (item_id)
ON DELETE NO ACTION
ON UPDATE NO ACTION
NOT DEFERRABLE;

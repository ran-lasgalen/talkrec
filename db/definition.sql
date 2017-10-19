--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;

SET search_path = public, pg_catalog;

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: employee; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE employee (
    id integer NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    mapid integer
);


--
-- Name: employee_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE employee_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: employee_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE employee_id_seq OWNED BY employee.id;


--
-- Name: phrase; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE phrase (
    id integer NOT NULL,
    regexp text NOT NULL,
    description text NOT NULL,
    desired boolean NOT NULL,
    category_id integer
);


--
-- Name: phrase_category; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE phrase_category (
    id integer NOT NULL,
    title text
);


--
-- Name: phrase_category_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE phrase_category_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: phrase_category_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE phrase_category_id_seq OWNED BY phrase_category.id;


--
-- Name: phrase_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE phrase_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: phrase_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE phrase_id_seq OWNED BY phrase.id;


--
-- Name: phrase_talk; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE phrase_talk (
    phrase_id integer,
    talk_id integer,
    n integer NOT NULL
);


--
-- Name: record_station; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE record_station (
    ip inet NOT NULL,
    site_id integer,
    headset integer
);


--
-- Name: site; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE site (
    id integer NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL,
    mapid integer
);


--
-- Name: site_employee; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE site_employee (
    site_id integer,
    employee_id integer
);


--
-- Name: site_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE site_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE site_id_seq OWNED BY site.id;


--
-- Name: talk; Type: TABLE; Schema: public; Owner: -; Tablespace: 
--

CREATE TABLE talk (
    id integer NOT NULL,
    talk text,
    started_at timestamp with time zone,
    made_on date NOT NULL,
    duration double precision,
    employee_id integer,
    site_id integer,
    headset integer,
    filename text,
    extra jsonb
);


--
-- Name: talk_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE talk_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: talk_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE talk_id_seq OWNED BY talk.id;


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY employee ALTER COLUMN id SET DEFAULT nextval('employee_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY phrase ALTER COLUMN id SET DEFAULT nextval('phrase_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY phrase_category ALTER COLUMN id SET DEFAULT nextval('phrase_category_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY site ALTER COLUMN id SET DEFAULT nextval('site_id_seq'::regclass);


--
-- Name: id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY talk ALTER COLUMN id SET DEFAULT nextval('talk_id_seq'::regclass);


--
-- Name: employee_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY employee
    ADD CONSTRAINT employee_pkey PRIMARY KEY (id);


--
-- Name: phrase_category_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY phrase_category
    ADD CONSTRAINT phrase_category_pkey PRIMARY KEY (id);


--
-- Name: phrase_category_title_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY phrase_category
    ADD CONSTRAINT phrase_category_title_key UNIQUE (title);


--
-- Name: phrase_description_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY phrase
    ADD CONSTRAINT phrase_description_key UNIQUE (description);


--
-- Name: phrase_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY phrase
    ADD CONSTRAINT phrase_pkey PRIMARY KEY (id);


--
-- Name: phrase_talk_phraseid_talkid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY phrase_talk
    ADD CONSTRAINT phrase_talk_phraseid_talkid_key UNIQUE (phrase_id, talk_id);


--
-- Name: record_station_ip_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY record_station
    ADD CONSTRAINT record_station_ip_key UNIQUE (ip);


--
-- Name: record_station_siteid_headset_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY record_station
    ADD CONSTRAINT record_station_siteid_headset_key UNIQUE (site_id, headset);


--
-- Name: site_employee_siteid_employeeid_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY site_employee
    ADD CONSTRAINT site_employee_siteid_employeeid_key UNIQUE (site_id, employee_id);


--
-- Name: site_name_key; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY site
    ADD CONSTRAINT site_name_key UNIQUE (name);


--
-- Name: site_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY site
    ADD CONSTRAINT site_pkey PRIMARY KEY (id);


--
-- Name: talk_pkey; Type: CONSTRAINT; Schema: public; Owner: -; Tablespace: 
--

ALTER TABLE ONLY talk
    ADD CONSTRAINT talk_pkey PRIMARY KEY (id);


--
-- Name: phrase_categoryid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY phrase
    ADD CONSTRAINT phrase_categoryid_fkey FOREIGN KEY (category_id) REFERENCES phrase_category(id) ON UPDATE CASCADE;


--
-- Name: phrase_talk_phraseid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY phrase_talk
    ADD CONSTRAINT phrase_talk_phraseid_fkey FOREIGN KEY (phrase_id) REFERENCES phrase(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: phrase_talk_talkid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY phrase_talk
    ADD CONSTRAINT phrase_talk_talkid_fkey FOREIGN KEY (talk_id) REFERENCES talk(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: record_station_siteid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY record_station
    ADD CONSTRAINT record_station_siteid_fkey FOREIGN KEY (site_id) REFERENCES site(id) ON UPDATE CASCADE ON DELETE SET NULL;


--
-- Name: site_employee_employeeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY site_employee
    ADD CONSTRAINT site_employee_employeeid_fkey FOREIGN KEY (employee_id) REFERENCES employee(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: site_employee_siteid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY site_employee
    ADD CONSTRAINT site_employee_siteid_fkey FOREIGN KEY (site_id) REFERENCES site(id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: talk_emloyeeid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY talk
    ADD CONSTRAINT talk_emloyeeid_fkey FOREIGN KEY (employee_id) REFERENCES employee(id) ON UPDATE CASCADE;


--
-- Name: talk_siteid_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY talk
    ADD CONSTRAINT talk_siteid_fkey FOREIGN KEY (site_id) REFERENCES site(id) ON UPDATE CASCADE;


--
-- PostgreSQL database dump complete
--


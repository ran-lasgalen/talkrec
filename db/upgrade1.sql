alter table talk add unique (filename);
create index on talk (made_on, started_at);

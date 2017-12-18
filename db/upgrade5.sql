alter table phrase_talk alter column phrase_id set not null;
alter table phrase_talk alter column talk_id set not null;
alter table site_employee alter column site_id set not null;
alter table site_employee alter column employee_id set not null;
alter table phrase_category alter column ord set not null;
alter table phrase_category alter column title set not null;
alter table talk add column analyzed boolean not null default false;
alter table phrase add column analyzed boolean not null default false;

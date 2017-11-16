alter table phrase_category add column ord integer unique;
insert into phrase_category (title, ord) values
  ('Приветствие',1),
  ('Установление контакта',2),
  ('Выявление потребности',3),
  ('Презентация',4),
  ('Работа с возражением',5),
  ('Завершение',6);

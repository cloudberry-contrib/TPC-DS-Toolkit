select query_id, 
case when bool_or(session_1_error) then 'ERROR' else sum(session_1)::text end as session_1,
case when bool_or(session_2_error) then 'ERROR' else sum(session_2)::text end as session_2,
case when bool_or(session_3_error) then 'ERROR' else sum(session_3)::text end as session_3,
case when bool_or(session_4_error) then 'ERROR' else sum(session_4)::text end as session_4,
case when bool_or(session_5_error) then 'ERROR' else sum(session_5)::text end as session_5,
case when bool_or(session_6_error) then 'ERROR' else sum(session_6)::text end as session_6,
case when bool_or(session_7_error) then 'ERROR' else sum(session_7)::text end as session_7,
case when bool_or(session_8_error) then 'ERROR' else sum(session_8)::text end as session_8,
case when bool_or(session_9_error) then 'ERROR' else sum(session_9)::text end as session_9,
case when bool_or(session_10_error) then 'ERROR' else sum(session_10)::text end as session_10
from	(
	select split_part(description, '.', 2) as query_id, 
	case when split_part(description, '.', 1) = '1' then round(extract('epoch' from duration)) else 0 end as session_1,
	case when split_part(description, '.', 1) = '1' and tuples = -1 then true else false end as session_1_error,
	case when split_part(description, '.', 1) = '2' then round(extract('epoch' from duration)) else 0 end as session_2,
	case when split_part(description, '.', 1) = '2' and tuples = -1 then true else false end as session_2_error,
	case when split_part(description, '.', 1) = '3' then round(extract('epoch' from duration)) else 0 end as session_3,
	case when split_part(description, '.', 1) = '3' and tuples = -1 then true else false end as session_3_error,
	case when split_part(description, '.', 1) = '4' then round(extract('epoch' from duration)) else 0 end as session_4,
	case when split_part(description, '.', 1) = '4' and tuples = -1 then true else false end as session_4_error,
	case when split_part(description, '.', 1) = '5' then round(extract('epoch' from duration)) else 0 end as session_5,
	case when split_part(description, '.', 1) = '5' and tuples = -1 then true else false end as session_5_error,
	case when split_part(description, '.', 1) = '6' then round(extract('epoch' from duration)) else 0 end as session_6,
	case when split_part(description, '.', 1) = '6' and tuples = -1 then true else false end as session_6_error,
	case when split_part(description, '.', 1) = '7' then round(extract('epoch' from duration)) else 0 end as session_7,
	case when split_part(description, '.', 1) = '7' and tuples = -1 then true else false end as session_7_error,
	case when split_part(description, '.', 1) = '8' then round(extract('epoch' from duration)) else 0 end as session_8,
	case when split_part(description, '.', 1) = '8' and tuples = -1 then true else false end as session_8_error,
	case when split_part(description, '.', 1) = '9' then round(extract('epoch' from duration)) else 0 end as session_9,
	case when split_part(description, '.', 1) = '9' and tuples = -1 then true else false end as session_9_error,
	case when split_part(description, '.', 1) = '10' then round(extract('epoch' from duration)) else 0 end as session_10,
	case when split_part(description, '.', 1) = '10' and tuples = -1 then true else false end as session_10_error
	from :multi_user_report_schema.sql
	) as sub
group by query_id
order by 1;

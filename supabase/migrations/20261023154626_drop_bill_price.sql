set local check_function_bodies = off;

drop function "private"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
  with time zone);

drop function "public"."arena_bill_price"(uuid, uuid, timestamp with time zone, timestamp
  with time zone);

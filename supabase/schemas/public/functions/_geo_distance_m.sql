-- _geo_distance_m(lat1, lng1, lat2, lng2) — great-circle distance in whole metres
--
-- Haversine on a sphere of the mean Earth radius (6,371,008.8 m); accurate to
-- well under a metre at geofence scale (tens to hundreds of metres), which is
-- far below GPS accuracy. Used by op_attendance_punch to compare a punch with the
-- arena's geofence centre. Null in, null out.
-- Server-only: not executable by anon/authenticated.
create or replace function public._geo_distance_m (
  p_lat1 double precision,
  p_lng1 double precision,
  p_lat2 double precision,
  p_lng2 double precision
)
  returns integer
  language sql
  immutable
  strict
  set search_path to 'public'
  AS $function$
  select round(2 * 6371008.8 * asin(least(1, sqrt(
           power(sin(radians(p_lat2 - p_lat1) / 2), 2)
         + cos(radians(p_lat1)) * cos(radians(p_lat2))
           * power(sin(radians(p_lng2 - p_lng1) / 2), 2)))))::int;
$function$;

comment on function public._geo_distance_m(double precision, double precision, double precision, double precision) is 'Internal: haversine distance in whole metres between two lat/lng points; used for the attendance geofence.';

grant execute on function "public"."_geo_distance_m"(double precision, double precision, double precision, double precision) to "postgres", "service_role";

revoke all on function "public"."_geo_distance_m"(double precision, double precision, double precision, double precision) from public;

revoke all on function "public"._geo_distance_m(p_lat1 double precision, p_lng1 double precision, p_lat2 double precision, p_lng2 double precision) from anon;

revoke all on function "public"._geo_distance_m(p_lat1 double precision, p_lng1 double precision, p_lat2 double precision, p_lng2 double precision) from authenticated;

alter table "public"."leave_adjustments"
  drop constraint "leave_adjustments_staff_id_fkey";

alter table "public"."leave_requests"
  drop constraint "leave_requests_staff_id_fkey";

alter table "public"."salary_adjustments"
  drop constraint "salary_adjustments_staff_id_fkey";

alter table "public"."salary_deduction_decisions"
  drop constraint "salary_deduction_decisions_staff_id_fkey";

alter table "public"."salary_run_lines"
  drop constraint "salary_run_lines_staff_id_fkey";

alter table "public"."staff_hr_profiles"
  drop constraint "staff_hr_profiles_staff_id_fkey";

alter table "public"."staff_pay_rates"
  drop constraint "staff_pay_rates_staff_id_fkey";

alter table "public"."staff_personal_details"
  drop constraint "staff_personal_details_staff_id_fkey";

alter table "public"."staff_shifts"
  drop constraint "staff_shifts_staff_id_fkey";

alter table "public"."staff_terms_acceptances"
  drop constraint "staff_terms_acceptances_staff_id_fkey";

alter table "public"."leave_adjustments"
  add constraint "leave_adjustments_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."leave_requests"
  add constraint "leave_requests_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."salary_adjustments"
  add constraint "salary_adjustments_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."salary_deduction_decisions"
  add constraint "salary_deduction_decisions_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."salary_run_lines"
  add constraint "salary_run_lines_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."staff_hr_profiles"
  add constraint "staff_hr_profiles_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."staff_pay_rates"
  add constraint "staff_pay_rates_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."staff_personal_details"
  add constraint "staff_personal_details_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."staff_shifts"
  add constraint "staff_shifts_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

alter table "public"."staff_terms_acceptances"
  add constraint "staff_terms_acceptances_staff_id_fkey" foreign key (staff_id)
    references public.staff_profiles(id);

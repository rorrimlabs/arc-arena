create trigger t_attendance_punches_append_only
  before delete or update on public.attendance_punches
  for each row
  execute function public._append_only();

create trigger t_audit_log_append_only
  before delete or update on public.audit_log
  for each row
  execute function public._append_only();

create trigger t_controller_moves_append_only
  before delete or update on public.controller_moves
  for each row
  execute function public._append_only();

create trigger t_salary_adjustments_append_only
  before delete or update on public.salary_adjustments
  for each row
  execute function public._append_only();

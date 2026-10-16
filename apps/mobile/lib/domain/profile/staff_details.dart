/// A staff member's own personal details: contact, date of birth, blood
/// group, address and an emergency contact. Every field is optional; the
/// server keeps the same rules as [invalidStaffDetails] (op_staff_details_save).
library;

import 'package:arena_ops/core/time/ist.dart';
import 'package:meta/meta.dart';

/// The fields of [StaffDetails], with their wire names and length limits.
enum StaffDetailsField {
  phone('phone', 'Phone'),
  email('email', 'Personal e-mail', maxLength: 254),
  birthDate('birth_date', 'Date of birth'),
  bloodGroup('blood_group', 'Blood group'),
  addressLine1('address_line1', 'Address line 1', maxLength: 200),
  addressLine2('address_line2', 'Address line 2', maxLength: 200),
  city('city', 'City', maxLength: 80),
  state('state', 'State', maxLength: 80),
  pinCode('pin_code', 'PIN code', maxLength: 6),
  emergencyName('emergency_name', 'Name', maxLength: 80),
  emergencyRelation('emergency_relation', 'Relation', maxLength: 40),
  emergencyPhone('emergency_phone', 'Phone');

  const StaffDetailsField(this.wire, this.label, {this.maxLength});
  final String wire;
  final String label;
  final int? maxLength;
}

const List<String> bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

@immutable
class StaffDetails {
  const StaffDetails({
    this.phone,
    this.email,
    this.birthDate,
    this.bloodGroup,
    this.addressLine1,
    this.addressLine2,
    this.city,
    this.state,
    this.pinCode,
    this.emergencyName,
    this.emergencyRelation,
    this.emergencyPhone,
  });

  /// No row yet: nothing filled in.
  static const empty = StaffDetails();

  final String? phone;
  final String? email;
  final IstDate? birthDate;
  final String? bloodGroup;
  final String? addressLine1;
  final String? addressLine2;
  final String? city;
  final String? state;
  final String? pinCode;
  final String? emergencyName;
  final String? emergencyRelation;
  final String? emergencyPhone;

  /// The text value of [f] (dates as YYYY-MM-DD), trimmed; null when blank.
  String? valueOf(StaffDetailsField f) {
    final v = switch (f) {
      StaffDetailsField.phone => phone,
      StaffDetailsField.email => email,
      StaffDetailsField.birthDate => birthDate?.iso,
      StaffDetailsField.bloodGroup => bloodGroup,
      StaffDetailsField.addressLine1 => addressLine1,
      StaffDetailsField.addressLine2 => addressLine2,
      StaffDetailsField.city => city,
      StaffDetailsField.state => state,
      StaffDetailsField.pinCode => pinCode,
      StaffDetailsField.emergencyName => emergencyName,
      StaffDetailsField.emergencyRelation => emergencyRelation,
      StaffDetailsField.emergencyPhone => emergencyPhone,
    }?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// Every field, so a blank one clears what was stored (the form edits the
  /// whole set). The server saves the caller's own row (no staff_id).
  Map<String, dynamic> toPayload() => {
        for (final f in StaffDetailsField.values) f.wire: valueOf(f) ?? '',
      };

  factory StaffDetails.fromJson(Map<String, dynamic> j) => StaffDetails(
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        birthDate: j['birth_date'] == null
            ? null
            : IstDate.parse(j['birth_date'] as String),
        bloodGroup: j['blood_group'] as String?,
        addressLine1: j['address_line1'] as String?,
        addressLine2: j['address_line2'] as String?,
        city: j['city'] as String?,
        state: j['state'] as String?,
        pinCode: j['pin_code'] as String?,
        emergencyName: j['emergency_name'] as String?,
        emergencyRelation: j['emergency_relation'] as String?,
        emergencyPhone: j['emergency_phone'] as String?,
      );
}

final _phone = RegExp(r'^\+?[0-9][0-9 -]{5,18}[0-9]$');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _pinCode = RegExp(r'^[1-9][0-9]{5}$');
const _earliestBirth = IstDate(1900, 1, 1);

/// The fields of [d] the server would refuse, in form order. A blank field
/// is never invalid (it clears the value). [today] is the IST date now.
List<StaffDetailsField> invalidStaffDetails(StaffDetails d, {required IstDate today}) => [
      for (final f in StaffDetailsField.values)
        if (d.valueOf(f) case final v? when !_valid(f, v, d, today)) f,
    ];

bool _valid(StaffDetailsField f, String v, StaffDetails d, IstDate today) {
  final max = f.maxLength;
  if (max != null && v.length > max) return false;
  return switch (f) {
    StaffDetailsField.phone || StaffDetailsField.emergencyPhone => _phone.hasMatch(v),
    StaffDetailsField.email => _email.hasMatch(v),
    StaffDetailsField.birthDate =>
      d.birthDate!.compareTo(_earliestBirth) >= 0 && d.birthDate!.compareTo(today) <= 0,
    StaffDetailsField.bloodGroup => bloodGroups.contains(v.toUpperCase()),
    StaffDetailsField.pinCode => _pinCode.hasMatch(v),
    _ => true,
  };
}

/// A save to send. [opId] makes a resend after a dropped connection replay
/// the same save; any edit needs a new one.
@immutable
class StaffDetailsCommand {
  const StaffDetailsCommand({required this.opId, required this.details});

  final String opId;
  final StaffDetails details;
}

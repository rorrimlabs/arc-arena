/// Phone vs tablet layout decisions in one place.
///
/// Phone = single column, one-handed. Tablet = wider, two-column floor where
/// useful (spec §1, §25). The breakpoint is the shortest width at which a
/// two-column counter layout is comfortable.
library;

import 'package:flutter/widgets.dart';

class Breakpoints {
  const Breakpoints._();
  static const double tablet = 720;
}

enum FormFactor { phone, tablet }

extension ResponsiveContext on BuildContext {
  FormFactor get formFactor =>
      MediaQuery.sizeOf(this).width >= Breakpoints.tablet
          ? FormFactor.tablet
          : FormFactor.phone;

  bool get isTablet => formFactor == FormFactor.tablet;
  bool get isPhone => formFactor == FormFactor.phone;
}

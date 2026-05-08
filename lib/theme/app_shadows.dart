import 'package:flutter/material.dart';

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x12081B16), blurRadius: 24, offset: Offset(0, 10)),
  ];

  static const soft = <BoxShadow>[
    BoxShadow(color: Color(0x10081B16), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static const floating = <BoxShadow>[
    BoxShadow(color: Color(0x18081B16), blurRadius: 32, offset: Offset(0, 16)),
  ];
}

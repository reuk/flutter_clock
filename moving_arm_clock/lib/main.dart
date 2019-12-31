import 'package:flutter/material.dart';
import 'package:flutter_clock_helper/customizer.dart';
import 'package:flutter_clock_helper/model.dart';

import 'moving_arm_clock.dart';

void main() =>
    runApp(ClockCustomizer((ClockModel model) => MovingArmClock(model)));

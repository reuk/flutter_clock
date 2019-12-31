import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_clock_helper/model.dart';
import 'package:intl/intl.dart';
import 'package:quiver/iterables.dart';

class _Segment<T extends num> {
  const _Segment(this.b, this.e);

  final Point<T> b;
  final Point<T> e;

  Point<T> otherEnd(Point<T> pt) {
    if (pt == b) {
      return e;
    }
    if (pt == e) {
      return b;
    }

    return null;
  }
}

class _Arms {
  _Arms(this.arms, this.start)
      : angles = arms.map((List<int> lst) => _angles(start, lst)).toList();

  int numMatches(_Arms other) =>
      zip(<List<Float32List>>[angles, other.angles]).fold(
          0,
          (int acc, List<Float32List> pair) =>
              acc + _numMatches(pair[0], pair[1]));

  static int _numMatches<T extends num>(List<T> x, List<T> y) =>
      zip(<List<T>>[x, y]).where((List<T> lst) => lst[0] == lst[1]).length;

  static Float32List _angles(Point<int> start, List<int> segments) {
    final Float32List result = Float32List(segments.length);
    Point<int> pos = start;
    double prevAngle = 0.0;
    int index = 0;

    for (final int seg in segments) {
      final Point<int> newPos = _segments[seg].otherEnd(pos);
      final Point<int> diff = newPos - pos;
      final double thisAngle = atan2(diff.y, diff.x);
      result[index] = thisAngle - prevAngle;
      pos = newPos;
      prevAngle = thisAngle;
      index += 1;
    }

    return result;
  }

  // segment layout
  // +0+
  // 1 2
  // +3+
  // 4 5
  // +6+

  static const List<_Segment<int>> _segments = <_Segment<int>>[
    _Segment<int>(Point<int>(0, 0), Point<int>(1, 0)),
    _Segment<int>(Point<int>(0, 0), Point<int>(0, 1)),
    _Segment<int>(Point<int>(1, 0), Point<int>(1, 1)),
    _Segment<int>(Point<int>(0, 1), Point<int>(1, 1)),
    _Segment<int>(Point<int>(0, 1), Point<int>(0, 2)),
    _Segment<int>(Point<int>(1, 1), Point<int>(1, 2)),
    _Segment<int>(Point<int>(0, 2), Point<int>(1, 2)),
  ];

  static const List<List<int>> _numbers = <List<int>>[
    <int>[0, 1, 2, 4, 5, 6],
    <int>[2, 5],
    <int>[0, 2, 3, 4, 6],
    <int>[0, 2, 3, 5, 6],
    <int>[1, 2, 3, 5],
    <int>[0, 1, 3, 5, 6],
    <int>[0, 1, 3, 4, 5, 6],
    <int>[0, 2, 5],
    <int>[0, 1, 2, 3, 4, 5, 6],
    <int>[0, 1, 2, 3, 5, 6],
  ];

  static List<List<int>> _computePotentialArm(
      Point<int> start, int digit, int length) {
    if (length == 0) {
      return <List<int>>[<int>[]];
    }

    return _numbers[digit]
        .where((int ind) => _segments[ind].otherEnd(start) != null)
        .expand((int ind) => _computePotentialArm(
                _segments[ind].otherEnd(start), digit, length - 1)
            .map((List<int> lst) => <int>[ind] + lst))
        .toList();
  }

  static List<_Arms> _computePotentialArms(
      Point<int> start, int digit, int lengthA, int lengthB) {
    final List<List<int>> armsA = _computePotentialArm(start, digit, lengthA);
    final List<List<int>> armsB = _computePotentialArm(start, digit, lengthB);
    final Set<int> requiredSegments = Set<int>.from(_numbers[digit]);

    final List<_Arms> result = <_Arms>[];

    for (final List<int> potentialA in armsA) {
      for (final List<int> potentialB in armsB) {
        if (requiredSegments
            .difference(Set<int>.from(potentialA + potentialB))
            .isEmpty) {
          result.add(_Arms(<List<int>>[potentialA, potentialB], start));
        }
      }
    }

    return result;
  }

  static _Arms findBestConfiguration(_Arms current, int digit) {
    final List<_Arms> possibilities = _computePotentialArms(
        current.start, digit, current.arms[0].length, current.arms[1].length);
    possibilities.shuffle();
    possibilities.sort((_Arms a, _Arms b) =>
        -current.numMatches(a).compareTo(current.numMatches(b)));
    return possibilities[0];
  }

  final Point<int> start;
  final List<List<int>> arms;
  final List<Float32List> angles;
}

class _DrawnSegment extends StatelessWidget {
  const _DrawnSegment({
    @required this.segmentLength,
    @required this.startOffset,
    @required this.head,
    @required this.tail,
    @required this.bg,
    @required this.fg,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: SizedBox.expand(
          child: CustomPaint(
            isComplex: true,
            willChange: true,
            painter: _DrawnSegmentPainter(
              segmentLength: segmentLength,
              startOffset: startOffset,
              head: head,
              tail: tail,
              bg: bg,
              fg: fg,
            ),
          ),
        ),
      );

  final double segmentLength;
  final Offset startOffset;
  final Float32List head;
  final Float32List tail;
  final Color bg;
  final Color fg;
}

class _DrawnSegmentPainter extends CustomPainter {
  _DrawnSegmentPainter({
    @required this.segmentLength,
    @required this.startOffset,
    @required this.head,
    @required this.tail,
    @required this.bg,
    @required this.fg,
  });

  @override
  void paint(Canvas canvas, Size s) {
    final double length = s.width * segmentLength;
    final Offset pos = (Offset.zero & s).center + startOffset * length;
    final List<List<Offset>> lines =
        _computeLines(head, length, pos).reversed.toList() +
            _computeLines(tail, length, pos);
    final List<Offset> lineSegments = <Offset>[lines.first[1]];

    for (final List<Offset> line in lines)
      lineSegments.add(line[line[0] != lineSegments.last ? 0 : 1]);

    final double width = length * 0.8;

    final Path path = () {
      final Path p = Path();
      p.moveTo(lineSegments.first.dx, lineSegments.first.dy);

      for (final Offset pos in lineSegments.sublist(1)) {
        p.lineTo(pos.dx, pos.dy);
      }

      return p;
    }();

    final Offset shadowOffset = Offset.fromDirection(pi / 4, width * 0.2);
    const int numShadows = 2;

    for (int i = 0; i != numShadows; ++i) {
      canvas.drawPath(
          path.shift(shadowOffset * (numShadows - i.toDouble())),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Color.lerp(fg, bg, lerpDouble(0.8, 0.5, i / numShadows))
            ..strokeWidth = width
            ..strokeJoin = StrokeJoin.round
            ..strokeCap = StrokeCap.round);
    }

    int index = 0;

    for (final List<Offset> line in lines) {
      canvas.drawLine(
          line[0],
          line[1],
          Paint()
            ..color = Color.lerp(
                bg,
                fg,
                lerpDouble(
                    1.0, 0.5, (index / (lines.length - 1.0)) * 0.5 + 0.5))
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round);

      index += 1;
    }
  }

  static List<List<Offset>> _computeLines(
      Float32List angles, double length, Offset pos) {
    final List<List<Offset>> linesToDraw = <List<Offset>>[];
    double currentAngle = 0.0;

    for (final double angle in angles) {
      currentAngle = (currentAngle + angle).remainder(2 * pi);
      final Offset end =
          pos + Offset(cos(currentAngle), sin(currentAngle)) * length;
      linesToDraw.add(<Offset>[pos, end]);
      pos = end;
    }

    return linesToDraw;
  }

  @override
  bool shouldRepaint(_DrawnSegmentPainter old) => old != this;

  @override
  bool operator ==(dynamic other) =>
      other is _DrawnSegmentPainter &&
      segmentLength == other.segmentLength &&
      head == other.head &&
      tail == other.tail;

  @override
  int get hashCode => hashValues(segmentLength, head, tail);

  final double segmentLength;
  final Offset startOffset;
  final Float32List head;
  final Float32List tail;
  final Color bg;
  final Color fg;
}

class _AnimatedArm extends StatefulWidget {
  _AnimatedArm({
    this.initialConfig = 0,
    this.mass = 20,
    @required Stream<int> digit,
  }) : digitStream = digit.distinct();

  @override
  State createState() => _AnimatedArmState();

  final int initialConfig;
  final double mass;
  final Stream<int> digitStream;
}

class _AnimatedArmState extends State<_AnimatedArm>
    with SingleTickerProviderStateMixin {
  _Arms _arms;
  AnimationController _controller;
  StreamSubscription<int> _subscription;

  final double _segmentLength = 0.5;

  List<Float32List> _lastAngles;
  List<Float32List> _nextAngles;

  final List<_Arms> _initialConfigurations = <_Arms>[
    _Arms(<List<int>>[
      <int>[2],
      <int>[2, 2, 2, 2, 2, 2]
    ], const Point<int>(1, 0)),
    _Arms(<List<int>>[
      <int>[2, 2, 2],
      <int>[2, 2, 2, 2]
    ], const Point<int>(1, 1)),
    _Arms(<List<int>>[
      <int>[5],
      <int>[5, 5, 5, 5, 5, 5]
    ], const Point<int>(1, 2)),
  ];

  @override
  void initState() {
    super.initState();
    _arms = _initialConfigurations[widget.initialConfig];
    _lastAngles = _nextAngles = _arms.angles;
    _controller = AnimationController.unbounded(vsync: this);
    _controller.addListener(() => setState(() {}));
    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.digitStream.listen((int digit) => setState(() {
          _arms = _Arms.findBestConfiguration(_arms, digit);
          _lastAngles = angles;
          _nextAngles = _arms.angles;
          _controller.animateWith(SpringSimulation(
              SpringDescription(mass: widget.mass, stiffness: 10, damping: 1),
              0,
              1,
              0));
        }));
  }

  @override
  void dispose() {
    _controller.dispose();
    _subscription.cancel();
    super.dispose();
  }

  List<Float32List>
      get angles => zip(<List<Float32List>>[_lastAngles, _nextAngles])
          .map((List<Float32List> pair) =>
              _lerp(pair[0], pair[1], _controller.value))
          .toList();

  @override
  Widget build(BuildContext ctx) {
    final Palette colors = Theme.of(context).brightness == Brightness.light
        ? _lightTheme
        : _darkTheme;

    return _DrawnSegment(
      segmentLength: _segmentLength,
      startOffset: Offset(_arms.start.x.toDouble(), _arms.start.y.toDouble()) -
          const Offset(0.5, 1),
      head: angles[0],
      tail: angles[1],
      bg: colors.background,
      fg: colors.foreground,
    );
  }

  static Float32List _lerp(Float32List a, Float32List b, double value) =>
      Float32List.fromList(zip(<Float32List>[a, b]).map((List<double> lst) {
        final double diff = (lst[1] - lst[0] + 3 * pi).remainder(2 * pi) - pi;
        final double correctedDiff = diff < -pi ? diff + 2 * pi : diff;
        return correctedDiff * value + lst[0];
      }).toList());
}

class Palette {
  Palette({
    this.background,
    this.foreground,
  });

  Color background;
  Color foreground;
}

final Palette _lightTheme = Palette(
  background: Colors.indigo[50],
  foreground: Colors.purple,
);

final Palette _darkTheme = Palette(
  background: Colors.grey[900],
  foreground: Colors.cyan,
);

class MovingArmClock extends StatefulWidget {
  const MovingArmClock(this.model);

  final ClockModel model;

  @override
  _MovingArmClockState createState() => _MovingArmClockState();
}

class _MovingArmClockState extends State<MovingArmClock> {
  Stream<DateTime> _seconds;
  StreamSubscription<DateTime> _semanticsSubscription;
  DateTime _time = DateTime.now();

  Stream<DateTime> get _secondStream async* {
    while (true) {
      final DateTime time = DateTime.now();
      yield time;
      await Future<void>.delayed(const Duration(seconds: 1) -
          Duration(milliseconds: time.millisecond));
    }
  }

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_updateModel);
    _seconds = _secondStream.asBroadcastStream();
    _semanticsSubscription =
        _seconds.listen((DateTime time) => setState(() => _time = time));
    _updateModel();
  }

  @override
  void didUpdateWidget(MovingArmClock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.model != oldWidget.model) {
      oldWidget.model.removeListener(_updateModel);
      widget.model.addListener(_updateModel);
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_updateModel);
    widget.model.dispose();
    _semanticsSubscription.cancel();
    super.dispose();
  }

  void _updateModel() => setState(() {});

  Widget _buildNumber({
    @required Function extractNum,
    @required Palette theme,
    double mass = 3,
    int flex = 10,
  }) {
    final Random random = Random();
    return Expanded(
      flex: flex,
      child: FractionallySizedBox(
        child: Row(
          children: <Widget>[
            Expanded(
              child: _AnimatedArm(
                  initialConfig: random.nextInt(3),
                  mass: mass,
                  digit: _seconds.map(
                      (DateTime time) => (extractNum(time) ~/ 10) % 10 as int)),
            ),
            Expanded(
              child: _AnimatedArm(
                  initialConfig: random.nextInt(3),
                  mass: mass,
                  digit: _seconds
                      .map((DateTime time) => extractNum(time) % 10 as int)),
            ),
          ],
        ),
        widthFactor: 0.85,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Palette colors = Theme.of(context).brightness == Brightness.light
        ? _lightTheme
        : _darkTheme;
    final double fontSize = MediaQuery.of(context).size.width * 0.032;
    final String time = DateFormat.Hm().format(DateTime.now());

    // I'd like to put an option to show the time, along with a
    // primary-color-picker, in the app settings but the ClockModel file
    // says that it shouldn't be edited by contestants.
    const bool showSeconds = false; // More interesting, also more distracting.

    return Semantics.fromProperties(
      properties: SemanticsProperties(
        label: 'Clock with time $time',
        value: time,
      ),
      child: Container(
        color: colors.background,
        child: Column(
          children: <Widget>[
            const Spacer(),
            Expanded(
              flex: 3,
              child: Center(
                child: FractionallySizedBox(
                  child: Row(
                    children: <Widget>[
                      _buildNumber(
                          extractNum: (DateTime time) => int.parse(DateFormat(
                                  widget.model.is24HourFormat as bool
                                      ? 'HH'
                                      : 'hh')
                              .format(time)),
                          theme: colors),
                      _buildNumber(
                          extractNum: (DateTime time) => time.minute,
                          theme: colors),
                      if (showSeconds)
                        _buildNumber(
                            extractNum: (DateTime time) => time.second,
                            mass: 15,
                            flex: 6,
                            theme: colors),
                    ],
                  ),
                  widthFactor: 0.9,
                ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: Text(
                  DateFormat.yMMMMEEEEd().format(_time),
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: fontSize,
                    fontWeight: FontWeight.normal,
                    color: colors.foreground.withOpacity(0.5),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'core.dart';

/// نقطة على الخريطة
class MapPin {
  final LatLng point;
  final String emoji;
  final Color color;
  final double size;
  final bool glow;
  final VoidCallback? onTap;
  const MapPin(this.point, this.emoji, {this.color = kGreen, this.size = 36, this.glow = false, this.onTap});
}

/// خريطة (OpenStreetMap) بستايل التطبيق
class OrodMap extends StatelessWidget {
  final LatLng? center;
  final double zoom;
  final List<MapPin> pins;
  final List<LatLng> route;
  final void Function(LatLng)? onTap;
  final MapController? controller;
  final double height;
  final String? hint;
  final bool fit;
  const OrodMap(
      {super.key,
      this.center,
      this.zoom = 14,
      this.pins = const [],
      this.route = const [],
      this.onTap,
      this.controller,
      this.height = 240,
      this.hint,
      this.fit = false});

  @override
  Widget build(BuildContext context) {
    final pts = pins.map((p) => p.point).toList();
    MapOptions options;
    if (fit && pts.length >= 2) {
      options = MapOptions(
        initialCameraFit: CameraFit.coordinates(coordinates: pts, padding: EdgeInsets.all(50), maxZoom: 16),
        onTap: onTap == null ? null : (_, ll) => onTap!(ll),
      );
    } else {
      options = MapOptions(
        initialCenter: center ?? (pts.isNotEmpty ? pts.first : kDefaultCenter),
        initialZoom: zoom,
        onTap: onTap == null ? null : (_, ll) => onTap!(ll),
      );
    }
    return Container(
      height: height,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: kLine)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: controller,
          options: options,
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.orod.sare3',
              tileBuilder: _darkTiles,
            ),
            if (route.length >= 2)
              PolylineLayer(polylines: [
                Polyline(points: route, color: kBlue, strokeWidth: 5, pattern: StrokePattern.dotted(spacingFactor: 2)),
              ]),
            MarkerLayer(markers: [
              for (final p in pins)
                Marker(
                  point: p.point,
                  width: p.size + (p.glow ? 24 : 0),
                  height: p.size + (p.glow ? 24 : 0),
                  child: GestureDetector(onTap: p.onTap, child: _pin(p)),
                ),
            ]),
          ],
        ),
        if (hint != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(10)),
              child: Text(hint!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        Positioned(
          bottom: 2,
          left: 6,
          child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: .7))),
        ),
      ]),
    );
  }

  Widget _pin(MapPin p) {
    final dot = Container(
      width: p.size,
      height: p.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: Alignment(-.3, -.4), colors: [Color.lerp(p.color, Colors.white, .35)!, p.color]),
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 6, offset: Offset(0, 3))],
      ),
      alignment: Alignment.center,
      child: Text(p.emoji, style: TextStyle(fontSize: p.size * 0.48)),
    );
    if (!p.glow) return dot;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: p.color.withValues(alpha: .25)),
      child: dot,
    );
  }
}

/// تغميق الخريطة شوية عشان تمشي مع ألوان التطبيق
Widget _darkTiles(BuildContext context, Widget tile, TileImage image) => ColorFiltered(
      colorFilter: ColorFilter.matrix(<double>[
        0.75, 0, 0, 0, 0, //
        0, 0.78, 0, 0, 0,
        0, 0, 0.9, 0, 8,
        0, 0, 0, 1, 0,
      ]),
      child: tile,
    );

/// شاشة تحديد مكان على الخريطة (دوس على الخريطة / موقعي الحالي / لصق لينك لوكيشن)
class PickLocationScreen extends StatefulWidget {
  final String title;
  final LatLng? initial;
  final LatLng? reference;
  final String refEmoji;
  const PickLocationScreen({super.key, required this.title, this.initial, this.reference, this.refEmoji = '🏪'});
  @override
  State<PickLocationScreen> createState() => _PickLocationScreenState();
}

class _PickLocationScreenState extends State<PickLocationScreen> {
  final ctrl = MapController();
  LatLng? point;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    point = widget.initial;
  }

  void _set(LatLng p, {bool move = false}) {
    setState(() => point = p);
    if (move) {
      try {
        ctrl.move(p, 16);
      } catch (_) {}
    }
  }

  Future<void> _gps() async {
    setState(() => busy = true);
    final p = await myLocation(context);
    if (mounted) setState(() => busy = false);
    if (p != null) _set(p, move: true);
  }

  Future<void> _paste() async {
    final t = await askText(context, 'الصق لينك اللوكيشن',
        hint: 'لينك جوجل ماب أو اللوكيشن اللي العميل بعته على واتساب', lines: 3);
    if (t == null || t.isEmpty) return;
    final p = parseLocation(t);
    if (p == null) {
      toast(context, 'مش لاقي إحداثيات في اللينك ده.. افتحه في جوجل ماب وانسخ اللينك الكامل أو دوس على الخريطة', error: true);
      return;
    }
    _set(p, move: true);
    toast(context, '📍 اتحدد المكان من اللينك');
  }

  @override
  Widget build(BuildContext context) {
    final pins = <MapPin>[
      if (widget.reference != null) MapPin(widget.reference!, widget.refEmoji, color: kPurple),
      if (point != null) MapPin(point!, '📍', color: kRed, size: 42, glow: true),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: OrodMap(
              controller: ctrl,
              center: point ?? widget.reference ?? kDefaultCenter,
              zoom: 15,
              height: double.infinity,
              pins: pins,
              onTap: (p) => _set(p),
              hint: '👆 دوس على المكان بالظبط',
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              if (point != null && widget.reference != null)
                Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                      'المسافة: ${kmTxt(kmBetween(widget.reference!.latitude, widget.reference!.longitude, point!.latitude, point!.longitude))}',
                      style: TextStyle(color: kOrange2, fontWeight: FontWeight.w800)),
                ),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                      onPressed: busy ? null : _gps,
                      icon: busy
                          ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.my_location),
                      label: Text('موقعي الحالي')),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(onPressed: _paste, icon: Icon(Icons.link), label: Text('لصق لينك لوكيشن')),
                ),
              ]),
              SizedBox(height: 10),
              Btn3D('حفظ المكان ✅', onTap: point == null ? null : () => Navigator.pop(context, point)),
            ]),
          ),
        ),
      ]),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/runde.dart';
import '../services/friends_service.dart';
import '../services/location_service.dart';
import '../services/pin_renderer.dart';
import '../services/runden_service.dart';
import '../theme/dazu_colors.dart';
import '../widgets/dazu_wordmark.dart';
import '../widgets/runde_detail_sheet.dart';

/// Karten-Tab: Google-Maps mit allen aktiven Runden aus `/drops`.
/// Default-Kamera auf München, bis die User-Position durchkommt.
/// Floating lila dazu-Capsule links oben — identisch zum iOS-Pattern,
/// weil die Karte keine Hero-Headline hat.
class KarteScreen extends StatefulWidget {
  const KarteScreen({super.key});

  @override
  State<KarteScreen> createState() => _KarteScreenState();
}

class _KarteScreenState extends State<KarteScreen> {
  static const _munichFallback = CameraPosition(
    target: LatLng(48.1371, 11.5754),
    zoom: 13.5,
  );

  final RundenService _service = RundenService();
  final LocationService _location = LocationService();
  final FriendsService _friendsService = FriendsService();
  StreamSubscription<List<Runde>>? _rundenSub;
  StreamSubscription<List<Freund>>? _friendsSub;
  GoogleMapController? _mapController;

  Set<Marker> _rundenMarkers = {};
  Set<Marker> _friendMarkers = {};
  bool _didCenterOnUser = false;

  Set<Marker> get _markers => {..._rundenMarkers, ..._friendMarkers};

  @override
  void initState() {
    super.initState();
    _rundenSub = _service.watchAktiveRunden().listen((runden) async {
      if (!mounted) return;
      // Custom-Icons werden async gerendert — alle parallel, dann set.
      final entries = await Future.wait(runden.map((r) async {
        final icon = await PinRenderer.instance.pinForActivity(r.activityName);
        return Marker(
          markerId: MarkerId('runde:${r.id}'),
          position: LatLng(r.lat, r.lng),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          // Kein InfoWindow — Tap öffnet stattdessen das volle
          // RundeDetailSheet (Hero + Teilnehmer + Join/Leave).
          onTap: () => _openDetail(r),
        );
      }));
      if (!mounted) return;
      setState(() => _rundenMarkers = entries.toSet());
    });

    // Freundes-Pins — nur Freunde, die ihre location gesetzt haben.
    _friendsSub = _friendsService.watchFriends().listen((freunde) async {
      if (!mounted) return;
      final withLoc = freunde.where((f) => f.hasLocation).toList();
      final entries = await Future.wait(withLoc.map((f) async {
        final icon = await PinRenderer.instance.pinForFriend(
          uid: f.uid,
          name: f.name,
        );
        return Marker(
          markerId: MarkerId('friend:${f.uid}'),
          position: LatLng(f.lat!, f.lng!),
          icon: icon,
          anchor: const Offset(0.5, 0.5),
          infoWindow: InfoWindow(title: f.name),
        );
      }));
      if (!mounted) return;
      setState(() => _friendMarkers = entries.toSet());
    });
  }

  /// Beim ersten Map-Ready einmal auf die User-Position zoomen. Später
  /// nicht mehr automatisch (sonst reißt die Kamera dem User die Karte
  /// unter den Fingern weg).
  Future<void> _centerOnUserOnce() async {
    if (_didCenterOnUser) return;
    final pos = await _location.getCurrent();
    if (pos == null || _mapController == null || !mounted) return;
    _didCenterOnUser = true;
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(LatLng(pos.latitude, pos.longitude), 14.5),
    );
  }

  void _openDetail(Runde runde) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RundeDetailSheet(runde: runde),
    );
  }

  @override
  void dispose() {
    _rundenSub?.cancel();
    _friendsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: _munichFallback,
          onMapCreated: (c) {
            _mapController = c;
            _centerOnUserOnce();
          },
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 24,
          child: _buildFloatingBranding(),
        ),
        Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          right: 24,
          child: _buildLiveCount(),
        ),
        Positioned(
          right: 20,
          bottom: 24,
          child: _buildLocateButton(),
        ),
      ],
    );
  }

  Widget _buildLocateButton() {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          final pos = await _location.getCurrent();
          if (pos == null || _mapController == null || !mounted) return;
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(pos.latitude, pos.longitude),
              15,
            ),
          );
        },
        child: Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          child: const Icon(
            Icons.my_location,
            color: DazuColors.brandViolet,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingBranding() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: DazuColors.brandViolet,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: DazuColors.brandViolet.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: const DazuWordmark(
        height: 20,
        color: DazuColors.brandCream,
        dotColor: DazuColors.brandOrange,
      ),
    );
  }

  Widget _buildLiveCount() {
    final count = _markers.length;
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: DazuColors.brandViolet.withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: DazuColors.brandOrange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count live',
            style: GoogleFonts.bricolageGrotesque(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: DazuColors.brandNight,
            ),
          ),
        ],
      ),
    );
  }
}

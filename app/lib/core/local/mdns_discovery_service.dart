import 'package:multicast_dns/multicast_dns.dart';

/// A device found on the local network via mDNS (_aksabot._tcp).
class DiscoveredDevice {
  final String ip;
  final int port;
  final String hostName;

  const DiscoveredDevice({
    required this.ip,
    required this.port,
    required this.hostName,
  });

  String get statusUrl => 'http://$ip:$port/status';

  @override
  String toString() => 'DiscoveredDevice($ip:$port $hostName)';
}

/// Discovers Aksabot devices on the local network using mDNS.
///
/// The ESP32 registers itself under the service type `_aksabot._tcp` after
/// connecting to Wi-Fi. This service scans for that type and resolves the
/// device IP address.
class MdnsDiscoveryService {
  static const _serviceType = '_aksabot._tcp';

  /// Scan for all Aksabot devices on the local network.
  ///
  /// Returns a list of discovered devices (usually just one).
  /// Returns an empty list if none are found within [timeout].
  Future<List<DiscoveredDevice>> discoverAll({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final results = <DiscoveredDevice>[];
    final client = MDnsClient();

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(_serviceType),
          timeout: timeout)) {
        // Resolve SRV record to get hostname and port
        await for (final SrvResourceRecord srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
            timeout: const Duration(seconds: 2))) {
          // Resolve A record to get IPv4 address
          await for (final IPAddressResourceRecord addr
              in client.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(srv.target),
                  timeout: const Duration(seconds: 2))) {
            results.add(DiscoveredDevice(
              ip: addr.address.address,
              port: srv.port,
              hostName: srv.target,
            ));
            break; // one IP per host is enough
          }
          break; // one SRV per PTR is enough
        }
      }
    } catch (_) {
      // Fails gracefully when not on Wi-Fi or multicast is blocked
    } finally {
      client.stop();
    }

    return results;
  }

  /// Convenience: returns the first discovered device, or null.
  Future<DiscoveredDevice?> discoverFirst({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final all = await discoverAll(timeout: timeout);
    return all.isEmpty ? null : all.first;
  }
}

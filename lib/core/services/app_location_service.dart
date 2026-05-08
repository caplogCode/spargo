import 'app_location_service_stub.dart'
    if (dart.library.html) 'app_location_service_web.dart'
    if (dart.library.io) 'app_location_service_io.dart'
    as impl;
import 'app_location_types.dart';

AppLocationService createAppLocationService() =>
    impl.createAppLocationService();

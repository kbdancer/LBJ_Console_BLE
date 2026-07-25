import 'package:lbjconsole/util/loco_type_util.dart';

class LocoTypeService {
  static final LocoTypeService _instance = LocoTypeService._internal();
  factory LocoTypeService() => _instance;
  LocoTypeService._internal();

  Future<void> initialize() async {
    await LocoTypeUtil().initialize();
  }

  bool get isInitialized => LocoTypeUtil().isInitialized;
}

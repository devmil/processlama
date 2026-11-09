import 'dart:async';

import 'package:provider/provider.dart';

class ComponentCreationInfo<TContract, TImpl extends TContract> {
  ComponentCreationInfo({required this.creator, this.initializer});

  final Type contractType = TContract;
  final Type implType = TImpl;
  final TImpl Function() creator;
  final FutureOr<void> Function(TImpl)? initializer;

  TImpl? _instance;
  bool _initialized = false;

  Provider<TContract> get provider =>
      Provider<TContract>(create: (_) => instance);

  TImpl get instance {
    _instance ??= creator();
    return _instance!;
  }

  Future<void> maybeExecuteInitializer() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    await initializer?.call(instance);
  }
}

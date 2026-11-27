import 'cloud_provider.dart';

class CloudAuthorizationFailure extends CloudFailure {
  const CloudAuthorizationFailure() : super('私人云授权已失效，请在设置中的私人云重新授权；本机书籍已保留');
}

/// Inspect only to classify; never return or persist the raw SDK error.
bool requiresCloudSignIn(Object error) {
  if (error is CloudAuthorizationFailure) return true;
  final value = error.toString().toLowerCase();
  return value.contains('invalid_grant') ||
      value.contains('token has been expired or revoked') ||
      value.contains('请重新连接') ||
      value.contains('请连接 google drive') ||
      value.contains('授权不足');
}

String cloudFailureReason(Object error) =>
    requiresCloudSignIn(error) ? 'authorization_required' : 'operation_failed';

import 'package:firebase_auth/firebase_auth.dart';

// Firebase interface doubles for exercising the real ChatService transport.
class ChatTestAuth implements FirebaseAuth {
  final String? token;
  ChatTestAuth(this.token);

  @override
  User? get currentUser => token == null ? null : ChatTestUser(token!);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ChatTestUser implements User {
  final String token;
  ChatTestUser(this.token);

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => token;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

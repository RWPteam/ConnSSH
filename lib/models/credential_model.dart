class Credential {
  String id;
  String name;
  String username;
  AuthType authType;
  String? password;
  String? privateKey;
  String? passphrase; 

  Credential({
    required this.id,
    required this.name,
    required this.username,
    required this.authType,
    this.password,
    this.privateKey,
    this.passphrase,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Credential &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'authType': authType.toString(),
      'password': password,
      'privateKey': privateKey,
      'passphrase': passphrase,
    };
  }

  factory Credential.fromJson(Map<String, dynamic> json) {
    return Credential(
      id: json['id'],
      name: json['name'],
      username: json['username'],
      authType: AuthType.values.firstWhere(
        (e) => e.toString() == json['authType'],
        orElse: () => AuthType.password,
      ),
      password: json['password'],
      privateKey: json['privateKey'],
      passphrase: json['passphrase'],
    );
  }
}
enum AuthType {
  password,
  privateKey,
  passphrase,
}
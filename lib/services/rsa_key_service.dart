//rsa_key_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';

class RSAKeyService {
  static Map<String, dynamic> generateKeyPair(int keySize) {
    final keyGen = RSAKeyGenerator();
    final secureRandom = FortunaRandom();

    // 为随机数生成器添加种子
    final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));

    final keyParams = RSAKeyGeneratorParameters(
      BigInt.from(65537),
      keySize,
      64,
    );
    keyGen.init(ParametersWithRandom(keyParams, secureRandom));

    final keyPair = keyGen.generateKeyPair();
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;

    return {
      'private': privateKey,
      'public': publicKey,
    };
  }

  static String encodePrivateKeyToPemPKCS1(RSAPrivateKey key) {
    final asn1 = ASN1Sequence();
    asn1.add(ASN1Integer(BigInt.from(0))); // version
    asn1.add(ASN1Integer(key.modulus!));
    asn1.add(ASN1Integer(key.publicExponent!));
    asn1.add(ASN1Integer(key.privateExponent!));
    asn1.add(ASN1Integer(key.p!));
    asn1.add(ASN1Integer(key.q!));
    asn1.add(ASN1Integer(key.privateExponent! % (key.p! - BigInt.one)));
    asn1.add(ASN1Integer(key.privateExponent! % (key.q! - BigInt.one)));
    asn1.add(ASN1Integer(key.q!.modInverse(key.p!)));

    final base64 = base64Encode(asn1.encodedBytes);
    final lines = <String>[];
    for (var i = 0; i < base64.length; i += 64) {
      lines.add(
          base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }
    final pem = lines.join('\n');

    return '-----BEGIN RSA PRIVATE KEY-----\n$pem\n-----END RSA PRIVATE KEY-----';
  }

  static String encodePrivateKeyToPemPKCS8(RSAPrivateKey key) {
    final pkcs1Sequence = ASN1Sequence();
    pkcs1Sequence.add(ASN1Integer(BigInt.from(0)));
    pkcs1Sequence.add(ASN1Integer(key.modulus!));
    pkcs1Sequence.add(ASN1Integer(key.publicExponent!));
    pkcs1Sequence.add(ASN1Integer(key.privateExponent!));
    pkcs1Sequence.add(ASN1Integer(key.p!));
    pkcs1Sequence.add(ASN1Integer(key.q!));
    pkcs1Sequence
        .add(ASN1Integer(key.privateExponent! % (key.p! - BigInt.one)));
    pkcs1Sequence
        .add(ASN1Integer(key.privateExponent! % (key.q! - BigInt.one)));
    pkcs1Sequence.add(ASN1Integer(key.q!.modInverse(key.p!)));

    final algorithmSequence = ASN1Sequence();
    algorithmSequence
        .add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algorithmSequence.add(ASN1Null());

    final asn1 = ASN1Sequence();
    asn1.add(ASN1Integer(BigInt.from(0))); // version
    asn1.add(algorithmSequence);
    asn1.add(ASN1OctetString(pkcs1Sequence.encodedBytes));

    final base64 = base64Encode(asn1.encodedBytes);
    final lines = <String>[];
    for (var i = 0; i < base64.length; i += 64) {
      lines.add(
          base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }
    final pem = lines.join('\n');

    return '-----BEGIN PRIVATE KEY-----\n$pem\n-----END PRIVATE KEY-----';
  }

  static String encodePublicKeyToPem(RSAPublicKey key) {
    final algorithmSequence = ASN1Sequence();
    algorithmSequence
        .add(ASN1ObjectIdentifier.fromComponentString('1.2.840.113549.1.1.1'));
    algorithmSequence.add(ASN1Null());

    final asn1 = ASN1Sequence();
    asn1.add(algorithmSequence);

    // 添加一个前导0字节表示没有未使用的位
    final publicKeyBytes = encodeRSAPublicKeyToDER(key);
    final bitStringBytes = Uint8List(publicKeyBytes.length + 1);
    bitStringBytes[0] = 0; // 未使用的位数为0
    bitStringBytes.setRange(1, bitStringBytes.length, publicKeyBytes);
    asn1.add(ASN1BitString(bitStringBytes));

    final base64 = base64Encode(asn1.encodedBytes);
    final lines = <String>[];
    for (var i = 0; i < base64.length; i += 64) {
      lines.add(
          base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }
    final pem = lines.join('\n');

    return '-----BEGIN PUBLIC KEY-----\n$pem\n-----END PUBLIC KEY-----';
  }

  static Uint8List encodeRSAPublicKeyToDER(RSAPublicKey key) {
    final asn1 = ASN1Sequence();
    asn1.add(ASN1Integer(key.modulus!));
    asn1.add(ASN1Integer(key.publicExponent!));
    return Uint8List.fromList(asn1.encodedBytes);
  }

  // 使用PBKDF2生成密钥
  static encrypt.Key generateKeyFromPassword(String password, List<int> salt,
      {int iterations = 10000, int keyLength = 32}) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, keyLength));

    final keyBytes = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
    return encrypt.Key(keyBytes);
  }

  static String encryptPrivateKeyWithPassword(
      String privateKeyPem, String password,
      {int iterations = 10000}) {
    // 生成盐和IV
    final saltBytes = _generateSecureRandomBytes(16);
    final ivBytes = _generateSecureRandomBytes(16);

    // 使用PBKDF2生成密钥
    final key =
        generateKeyFromPassword(password, saltBytes, iterations: iterations);

    // 使用AES-CBC加密
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));
    final encrypted = encrypter.encrypt(privateKeyPem, iv: iv);

    // 构建PKCS#8加密私钥结构
    final keyDerivationFuncSequence = ASN1Sequence();
    keyDerivationFuncSequence.add(ASN1ObjectIdentifier.fromComponentString(
        '1.2.840.113549.1.5.12')); // pkcs5PBKDF2

    final pbkdf2ParamsSequence = ASN1Sequence();
    pbkdf2ParamsSequence.add(ASN1OctetString(saltBytes));
    pbkdf2ParamsSequence.add(ASN1Integer(BigInt.from(iterations))); // 迭代次数
    pbkdf2ParamsSequence.add(ASN1Integer(BigInt.from(32))); // 密钥长度（字节）

    final hmacSequence = ASN1Sequence();
    hmacSequence.add(ASN1ObjectIdentifier.fromComponentString(
        '1.2.840.113549.1.1.11')); // hmacWithSHA256

    pbkdf2ParamsSequence.add(hmacSequence);
    keyDerivationFuncSequence.add(pbkdf2ParamsSequence);

    final encryptionSchemeSequence = ASN1Sequence();
    encryptionSchemeSequence.add(ASN1ObjectIdentifier.fromComponentString(
        '2.16.840.1.101.3.4.1.42')); // aes256-CBC
    encryptionSchemeSequence.add(ASN1OctetString(ivBytes));

    final keyDerivationAndEncryptionSequence = ASN1Sequence();
    keyDerivationAndEncryptionSequence.add(keyDerivationFuncSequence);
    keyDerivationAndEncryptionSequence.add(encryptionSchemeSequence);

    final pbes2Sequence = ASN1Sequence();
    pbes2Sequence.add(ASN1ObjectIdentifier.fromComponentString(
        '1.2.840.113549.1.5.13')); // pkcs5PBES2
    pbes2Sequence.add(keyDerivationAndEncryptionSequence);

    final outerSequence = ASN1Sequence();
    outerSequence.add(pbes2Sequence);
    outerSequence.add(ASN1OctetString(encrypted.bytes));

    final base64 = base64Encode(outerSequence.encodedBytes);
    final lines = <String>[];
    for (var i = 0; i < base64.length; i += 64) {
      lines.add(
          base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }
    final pem = lines.join('\n');

    return '-----BEGIN ENCRYPTED PRIVATE KEY-----\n$pem\n-----END ENCRYPTED PRIVATE KEY-----';
  }

  // 解密使用PBKDF2加密的私钥
  static String decryptPrivateKeyWithPassword(
      String encryptedPem, String password) {
    // 提取PEM内容
    final lines = encryptedPem.split('\n');
    final base64Content =
        lines.where((line) => !line.startsWith('-----')).join('');
    final derBytes = base64Decode(base64Content);

    // 解析ASN.1结构
    final asn1Parser = ASN1Parser(Uint8List.fromList(derBytes));
    final outerSequence = asn1Parser.nextObject() as ASN1Sequence;
    final encryptionSequence = outerSequence.elements[0] as ASN1Sequence;
    final encryptedData = outerSequence.elements[1] as ASN1OctetString;

    // 提取加密算法参数
    final pbes2Sequence = encryptionSequence.elements[1] as ASN1Sequence;
    final keyDerivationFuncSequence = pbes2Sequence.elements[0] as ASN1Sequence;
    final encryptionSchemeSequence = pbes2Sequence.elements[1] as ASN1Sequence;

    // 提取PBKDF2参数
    final pbkdf2ParamsSequence =
        keyDerivationFuncSequence.elements[1] as ASN1Sequence;
    final salt =
        (pbkdf2ParamsSequence.elements[0] as ASN1OctetString).valueBytes();
    final iterations = (pbkdf2ParamsSequence.elements[1] as ASN1Integer)
        .valueAsBigInteger
        .toInt();

    // 提取加密参数
    final ivBytes =
        (encryptionSchemeSequence.elements[1] as ASN1OctetString).valueBytes();

    // 使用PBKDF2生成密钥
    final key = generateKeyFromPassword(password, salt, iterations: iterations);

    // 解密数据
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final decrypted = encrypter.decrypt(
        encrypt.Encrypted(Uint8List.fromList(encryptedData.valueBytes())),
        iv: iv);

    return decrypted;
  }

  // 生成安全随机字节
  static Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }
}

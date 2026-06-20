// ecdsa_key_service.dart
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:pointycastle/export.dart';
import 'package:asn1lib/asn1lib.dart';

class ECDSAKeyService {
  /// ECDSA曲线名称到标识符的映射
  static final Map<String, ECDomainParameters> _curveMap = {
    'p192': ECCurve_secp192r1(),
    'p224': ECCurve_secp224r1(),
    'p256': ECCurve_secp256r1(),
    'p384': ECCurve_secp384r1(),
    'p521': ECCurve_secp521r1(),
  };

  /// 生成ECDSA密钥对
  static Map<String, dynamic> generateKeyPair(String curveName) {
    try {
      final domainParams = _curveMap[curveName.toLowerCase()];
      if (domainParams == null) {
        throw Exception('不支持的曲线: $curveName');
      }

      // 创建密钥对生成器
      final keyGen = ECKeyGenerator();
      final secureRandom = FortunaRandom();

      // 添加随机种子
      final seed = List<int>.generate(32, (_) => Random.secure().nextInt(256));
      secureRandom.seed(KeyParameter(Uint8List.fromList(seed)));

      // 初始化生成器
      final keyParams = ECKeyGeneratorParameters(domainParams);
      keyGen.init(ParametersWithRandom(keyParams, secureRandom));

      // 生成密钥对
      final keyPair = keyGen.generateKeyPair();
      final privateKey = keyPair.privateKey as ECPrivateKey;
      final publicKey = keyPair.publicKey as ECPublicKey;

      return {
        'private': privateKey,
        'public': publicKey,
        'curve': curveName,
      };
    } catch (e) {
      throw Exception('生成ECDSA密钥对失败: $e');
    }
  }

  /// 将私钥编码为PKCS8格式的PEM
  static String encodePrivateKeyToPemPKCS8(ECPrivateKey key, String curveName) {
    try {
      // 创建AlgorithmIdentifier
      final algorithmSequence = ASN1Sequence();
      algorithmSequence.add(
        ASN1ObjectIdentifier.fromComponentString(
            '1.2.840.10045.2.1'), // ecPublicKey
      );

      // 添加曲线参数
      final curveOid = _getCurveOid(curveName);
      algorithmSequence.add(ASN1ObjectIdentifier.fromComponentString(curveOid));

      // 创建私钥数据
      final privateKeyValue = _intToBytes(key.d!);

      // 创建ECPrivateKey结构
      final ecPrivateKeySequence = ASN1Sequence();
      ecPrivateKeySequence.add(ASN1Integer(BigInt.from(1))); // version
      ecPrivateKeySequence.add(ASN1OctetString(privateKeyValue));

      // 添加参数（曲线）
      final parametersSequence = ASN1Sequence();
      parametersSequence
          .add(ASN1ObjectIdentifier.fromComponentString(curveOid));

      // 创建一个带标签的对象
      final parametersSequenceBytes = parametersSequence.encodedBytes;
      final taggedParameters = Uint8List(1 + parametersSequenceBytes.length);
      taggedParameters[0] = 0xA0; // 上下文特定的，构造的，标签0
      taggedParameters.setRange(
          1, taggedParameters.length, parametersSequenceBytes);

      // 添加公钥
      final publicKey = _getPublicKeyBytes(key);
      final bitString = Uint8List(publicKey.length + 1);
      bitString[0] = 0; // 未使用的位数为0
      bitString.setRange(1, bitString.length, publicKey);

      final bitStringBytes = bitString;
      final taggedPublicKey = Uint8List(1 + bitStringBytes.length);
      taggedPublicKey[0] = 0xA1; // 上下文特定的，构造的，标签1
      taggedPublicKey.setRange(1, taggedPublicKey.length, bitStringBytes);

      // 创建完整的PKCS#8结构
      final outerSequence = ASN1Sequence();
      outerSequence.add(ASN1Integer(BigInt.from(0))); // version
      outerSequence.add(algorithmSequence);

      // 创建私钥的octet string
      final privateKeyOctetString = ASN1OctetString(privateKeyValue);
      outerSequence.add(privateKeyOctetString);

      // 编码为PEM格式
      final base64 = base64Encode(outerSequence.encodedBytes);
      final lines = _splitBase64Lines(base64);

      return '-----BEGIN PRIVATE KEY-----\n$lines\n-----END PRIVATE KEY-----';
    } catch (e) {
      throw Exception('编码ECDSA私钥失败: $e');
    }
  }

  /// 将公钥编码为PEM格式
  static String encodePublicKeyToPem(ECPublicKey key, String curveName) {
    try {
      // 创建AlgorithmIdentifier
      final algorithmSequence = ASN1Sequence();
      algorithmSequence.add(
        ASN1ObjectIdentifier.fromComponentString(
            '1.2.840.10045.2.1'), // ecPublicKey
      );

      // 添加曲线参数
      final curveOid = _getCurveOid(curveName);
      algorithmSequence.add(ASN1ObjectIdentifier.fromComponentString(curveOid));

      // 编码公钥
      final publicKeyBytes = _encodeECPublicKey(key);

      // 创建SubjectPublicKeyInfo
      final asn1 = ASN1Sequence();
      asn1.add(algorithmSequence);

      final bitString = Uint8List(publicKeyBytes.length + 1);
      bitString[0] = 0; // 未使用的位数为0
      bitString.setRange(1, bitString.length, publicKeyBytes);
      asn1.add(ASN1BitString(bitString));

      // 编码为PEM格式
      final base64 = base64Encode(asn1.encodedBytes);
      final lines = _splitBase64Lines(base64);

      return '-----BEGIN PUBLIC KEY-----\n$lines\n-----END PUBLIC KEY-----';
    } catch (e) {
      throw Exception('编码ECDSA公钥失败: $e');
    }
  }

  /// 生成OpenSSH格式的公钥字符串
  static String encodePublicKeyToOpenSSH(ECPublicKey key, String curveName) {
    try {
      // 获取ECDSA类型的标识符
      final ecdsaIdentifier = _getOpenSSHCurveIdentifier(curveName);

      // 编码公钥
      final publicKeyBytes = _encodeECPublicKey(key);

      // 创建完整的OpenSSH公钥格式
      final keyTypeBytes = utf8.encode(ecdsaIdentifier);
      final keyData =
          Uint8List(4 + keyTypeBytes.length + 4 + publicKeyBytes.length);

      var offset = 0;

      // 写入密钥类型
      _writeUint32(keyData, offset, keyTypeBytes.length);
      offset += 4;
      keyData.setRange(offset, offset + keyTypeBytes.length, keyTypeBytes);
      offset += keyTypeBytes.length;

      // 写入公钥数据
      _writeUint32(keyData, offset, publicKeyBytes.length);
      offset += 4;
      keyData.setRange(offset, offset + publicKeyBytes.length, publicKeyBytes);

      final base64Key = base64Encode(keyData);
      return '$ecdsaIdentifier $base64Key generated-by-ssh-client';
    } catch (e) {
      throw Exception('编码OpenSSH公钥失败: $e');
    }
  }

  /// 使用密码加密私钥
  static String encryptPrivateKeyWithPassword(
      String privateKeyPem, String password,
      {int iterations = 10000}) {
    // 生成盐和IV
    final saltBytes = _generateSecureRandomBytes(16);
    final ivBytes = _generateSecureRandomBytes(16);

    // 使用PBKDF2生成密钥
    final key =
        _generateKeyFromPassword(password, saltBytes, iterations: iterations);

    // 使用AES-CBC加密
    final encrypter =
        encrypt.Encrypter(encrypt.AES(key, mode: encrypt.AESMode.cbc));
    final iv = encrypt.IV(Uint8List.fromList(ivBytes));
    final encrypted = encrypter.encrypt(privateKeyPem, iv: iv);

    // 构建PKCS#8加密私钥结构
    final keyDerivationFuncSequence = ASN1Sequence();
    keyDerivationFuncSequence.add(ASN1ObjectIdentifier.fromComponentString(
            '1.2.840.113549.1.5.12') // pkcs5PBKDF2
        );

    final pbkdf2ParamsSequence = ASN1Sequence();
    pbkdf2ParamsSequence.add(ASN1OctetString(saltBytes));
    pbkdf2ParamsSequence.add(ASN1Integer(BigInt.from(iterations)));
    pbkdf2ParamsSequence.add(ASN1Integer(BigInt.from(32))); // 密钥长度

    final hmacSequence = ASN1Sequence();
    hmacSequence.add(ASN1ObjectIdentifier.fromComponentString(
            '1.2.840.113549.1.1.11') // hmacWithSHA256
        );
    hmacSequence.add(ASN1Null());

    pbkdf2ParamsSequence.add(hmacSequence);
    keyDerivationFuncSequence.add(pbkdf2ParamsSequence);

    final encryptionSchemeSequence = ASN1Sequence();
    encryptionSchemeSequence.add(ASN1ObjectIdentifier.fromComponentString(
            '2.16.840.1.101.3.4.1.42') // aes256-CBC
        );
    encryptionSchemeSequence.add(ASN1OctetString(ivBytes));

    final keyDerivationAndEncryptionSequence = ASN1Sequence();
    keyDerivationAndEncryptionSequence.add(keyDerivationFuncSequence);
    keyDerivationAndEncryptionSequence.add(encryptionSchemeSequence);

    final pbes2Sequence = ASN1Sequence();
    pbes2Sequence.add(ASN1ObjectIdentifier.fromComponentString(
            '1.2.840.113549.1.5.13') // pkcs5PBES2
        );
    pbes2Sequence.add(keyDerivationAndEncryptionSequence);

    final outerSequence = ASN1Sequence();
    outerSequence.add(pbes2Sequence);
    outerSequence.add(ASN1OctetString(encrypted.bytes));

    final base64 = base64Encode(outerSequence.encodedBytes);
    final lines = _splitBase64Lines(base64);

    return '-----BEGIN ENCRYPTED PRIVATE KEY-----\n$lines\n-----END ENCRYPTED PRIVATE KEY-----';
  }

  // 获取曲线OID
  static String _getCurveOid(String curveName) {
    switch (curveName.toLowerCase()) {
      case 'p192':
      case 'secp192r1':
        return '1.2.840.10045.3.1.1'; // prime192v1
      case 'p224':
      case 'secp224r1':
        return '1.3.132.0.33'; // secp224r1
      case 'p256':
      case 'secp256r1':
        return '1.2.840.10045.3.1.7'; // prime256v1
      case 'p384':
      case 'secp384r1':
        return '1.3.132.0.34'; // secp384r1
      case 'p521':
      case 'secp521r1':
        return '1.3.132.0.35'; // secp521r1
      default:
        throw Exception('不支持的曲线: $curveName');
    }
  }

  /// 获取OpenSSH曲线标识符
  static String _getOpenSSHCurveIdentifier(String curveName) {
    switch (curveName.toLowerCase()) {
      case 'p256':
        return 'ecdsa-sha2-nistp256';
      case 'p384':
        return 'ecdsa-sha2-nistp384';
      case 'p521':
        return 'ecdsa-sha2-nistp521';
      default:
        throw Exception('OpenSSH不支持曲线: $curveName');
    }
  }

  /// 编码EC公钥
  static Uint8List _encodeECPublicKey(ECPublicKey key) {
    // EC公钥格式: 0x04 + x + y
    final x = key.Q!.x!.toBigInteger();
    final y = key.Q!.y!.toBigInteger();

    if (x == null || y == null) {
      throw Exception('无法获取公钥坐标');
    }

    final xBytes = _intToBytes(x);
    final yBytes = _intToBytes(y);

    final result = Uint8List(1 + xBytes.length + yBytes.length);
    result[0] = 0x04; // 未压缩格式
    result.setRange(1, 1 + xBytes.length, xBytes);
    result.setRange(1 + xBytes.length, result.length, yBytes);

    return result;
  }

  /// 从私钥获取公钥字节
  static Uint8List _getPublicKeyBytes(ECPrivateKey key) {
    final domainParams = key.parameters!;
    final publicPoint = domainParams.G * key.d!;
    final x = publicPoint?.x?.toBigInteger();
    final y = publicPoint?.y?.toBigInteger();

    if (x == null || y == null) {
      throw Exception('无法计算公钥点');
    }
    final xBytes = _intToBytes(x);
    final yBytes = _intToBytes(y);

    final result = Uint8List(1 + xBytes.length + yBytes.length);
    result[0] = 0x04; // 未压缩格式
    result.setRange(1, 1 + xBytes.length, xBytes);
    result.setRange(1 + xBytes.length, result.length, yBytes);

    return result;
  }

  /// 将大整数转换为字节数组
  static Uint8List _intToBytes(BigInt integer) {
    var hex = integer.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';

    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }

    return Uint8List.fromList(bytes);
  }

  /// 分割Base64字符串为多行
  static String _splitBase64Lines(String base64) {
    final lines = <String>[];
    for (var i = 0; i < base64.length; i += 64) {
      lines.add(
          base64.substring(i, i + 64 > base64.length ? base64.length : i + 64));
    }
    return lines.join('\n');
  }

  /// 写入32位无符号整数
  static void _writeUint32(Uint8List data, int offset, int value) {
    data[offset] = (value >> 24) & 0xFF;
    data[offset + 1] = (value >> 16) & 0xFF;
    data[offset + 2] = (value >> 8) & 0xFF;
    data[offset + 3] = value & 0xFF;
  }

  /// 生成安全随机字节
  static Uint8List _generateSecureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)));
  }

  /// 从密码生成密钥
  static encrypt.Key _generateKeyFromPassword(String password, List<int> salt,
      {int iterations = 10000, int keyLength = 32}) {
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(Uint8List.fromList(salt), iterations, keyLength));

    final keyBytes = pbkdf2.process(Uint8List.fromList(utf8.encode(password)));
    return encrypt.Key(keyBytes);
  }

  /// 验证曲线名称是否有效
  static bool isValidCurve(String curveName) {
    return _curveMap.containsKey(curveName.toLowerCase());
  }

  /// 获取所有支持的曲线名称
  static List<String> getSupportedCurves() {
    return _curveMap.keys.toList();
  }

  /// 获取曲线的密钥长度
  static int getCurveBitLength(String curveName) {
    switch (curveName.toLowerCase()) {
      case 'p192':
        return 192;
      case 'p224':
        return 224;
      case 'p256':
        return 256;
      case 'p384':
        return 384;
      case 'p521':
        return 521;
      default:
        return 256;
    }
  }
}

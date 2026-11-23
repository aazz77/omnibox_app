//! 音乐 SDK preload 注入的加密/编码 host 函数。
//! 契约对齐 lx-server（builtin-sdk-preload.js / user-api-preload.js 里的
//! __lx_native_call__utils_* 系列），数据用 base64 跨越 JS/Rust 边界。
use aes::Aes128;
use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use cbc::{Decryptor as CbcDec, Encryptor as CbcEnc};
use cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyIvInit, KeyInit};
use ecb::{Decryptor as EcbDec, Encryptor as EcbEnc};
use sha2::Digest;
use rsa::BigUint;
use rsa::traits::PublicKeyParts;
use rsa::RsaPublicKey;

pub fn b64d(s: &str) -> Vec<u8> { B64.decode(s).unwrap_or_default() }
pub fn b64e(b: &[u8]) -> String { B64.encode(b) }

fn hex_enc(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}
pub fn md5_hex(data: &[u8]) -> String {
    hex_enc(&md5::Md5::digest(data))
}
pub fn sha1_hex(data: &[u8]) -> String {
    hex_enc(&sha1::Sha1::digest(data))
}

/// str2md5: 参数是 encodeURIComponent 后的字符串，需先 URL 解码再算 md5
pub fn str2md5(s: &str) -> String {
    let decoded = percent_encoding::percent_decode_str(s).decode_utf8_lossy();
    md5_hex(decoded.as_bytes())
}
pub fn b64md5(s: &str) -> String { md5_hex(&b64d(s)) }
pub fn str2b64(s: &str) -> String { b64e(s.as_bytes()) }
pub fn b642buf(s: &str) -> String {
    let b = b64d(s);
    format!("[{}]", b.iter().map(|x| x.to_string()).collect::<Vec<_>>().join(","))
}

/// AES：mode 支持 CBC/PKCS7、ECB/PKCS7、ECB/NoPadding。key/iv/data 均 base64。
pub fn aes(mode: &str, enc: bool, data_b64: &str, key_b64: &str, iv_b64: &str) -> Result<String, String> {
    let data = b64d(data_b64);
    let mut key = b64d(key_b64);
    if key.len() != 16 { return Err(format!("AES key must be 16 bytes, got {}", key.len())); }
    key.resize(16, 0);
    let is_cbc = mode.contains("CBC") || mode.contains("Cbc");
    let no_pad = mode.eq("AES") || mode.to_lowercase().contains("nopadding");
    let k: &[u8; 16] = <&[u8; 16]>::try_from(key.as_slice()).unwrap();

    if is_cbc {
        let mut iv = b64d(iv_b64);
        iv.resize(16, 0);
        let iv_arr: &[u8; 16] = <&[u8; 16]>::try_from(iv.as_slice()).unwrap();
        if enc {
            let c = CbcEnc::<Aes128>::new(k.into(), iv_arr.into());
            let out = if no_pad {
                c.encrypt_padded_vec_mut::<cipher::block_padding::NoPadding>(&data)
            } else {
                c.encrypt_padded_vec_mut::<Pkcs7>(&data)
            };
            Ok(b64e(&out))
        } else {
            let c = CbcDec::<Aes128>::new(k.into(), iv_arr.into());
            let out = if no_pad {
                c.decrypt_padded_vec_mut::<cipher::block_padding::NoPadding>(&data)
            } else {
                c.decrypt_padded_vec_mut::<Pkcs7>(&data)
            }.map_err(|e| e.to_string())?;
            Ok(b64e(&out))
        }
    } else if enc {
        let c = EcbEnc::<Aes128>::new(k.into());
        let out = if no_pad {
            c.encrypt_padded_vec_mut::<cipher::block_padding::NoPadding>(&data)
        } else {
            c.encrypt_padded_vec_mut::<Pkcs7>(&data)
        };
        Ok(b64e(&out))
    } else {
        let c = EcbDec::<Aes128>::new(k.into());
        let out = if no_pad {
            c.decrypt_padded_vec_mut::<cipher::block_padding::NoPadding>(&data)
        } else {
            c.decrypt_padded_vec_mut::<Pkcs7>(&data)
        }.map_err(|e| e.to_string())?;
        Ok(b64e(&out))
    }
}

/// RSA/ECB/NoPadding：网易 weapi encSecKey 用。key 为去掉 PEM 头尾的 base64 (SPKI DER)。
pub fn rsa_no_padding(data_b64: &str, key: &str, _padding: &str) -> Result<String, String> {
    use rsa::pkcs8::DecodePublicKey;
    let clean: String = key.chars().filter(|c| !c.is_whitespace()).collect();
    let der = B64.decode(clean).map_err(|e| e.to_string())?;
    let pk = RsaPublicKey::from_public_key_der(&der)
        .map_err(|e| format!("RSA 公钥解析失败: {}", e))?;
    let n = pk.n();
    let e = pk.e();
    let m = BigUint::from_bytes_be(&b64d(data_b64));
    let c = m.modpow(e, n);
    let size = pk.size();
    let mut out = c.to_bytes_be();
    if out.len() < size {
        let mut pad = vec![0u8; size - out.len()];
        pad.extend_from_slice(&out);
        out = pad;
    }
    Ok(b64e(&out))
}

/// charset 解码：cs 形如 gbk / gb18030 / big5 / shift_jis / euc-kr / utf-8
pub fn decode_charset(b64: &str, cs: &str) -> String {
    let bytes = b64d(b64);
    let label = cs.to_ascii_lowercase();
    let enc = match label.as_str() {
        "gbk" | "gb2312" | "gb18030" => encoding_rs::GBK,
        "big5" | "big5-hkscs" => encoding_rs::BIG5,
        "shift_jis" | "sjis" => encoding_rs::SHIFT_JIS,
        "euc-kr" => encoding_rs::EUC_KR,
        "euc-jp" => encoding_rs::EUC_JP,
        _ => encoding_rs::UTF_8,
    };
    let (s, _, _) = enc.decode(&bytes);
    s.into_owned()
}
pub fn encode_charset(s: &str, cs: &str) -> String {
    let label = cs.to_ascii_lowercase();
    let enc = match label.as_str() {
        "gbk" | "gb2312" | "gb18030" => encoding_rs::GBK,
        "big5" | "big5-hkscs" => encoding_rs::BIG5,
        "shift_jis" | "sjis" => encoding_rs::SHIFT_JIS,
        "euc-kr" => encoding_rs::EUC_KR,
        _ => return b64e(s.as_bytes()),
    };
    let (b, _, _) = enc.encode(s);
    b64e(&b)
}

//! Independently implemented wire encryption. See the pinned protocol evidence.
use crate::Error;
use aes::cipher::{BlockDecrypt, BlockEncrypt, KeyInit, block_padding::Pkcs7};
use base64::{Engine, engine::general_purpose::STANDARD};
use cbc::cipher::{BlockEncryptMut, KeyIvInit};
use flate2::read::GzDecoder;
use md5::{Digest, Md5};
use num_bigint::BigUint;
use std::io::Read;

const MAX_DECODED_RESPONSE_BYTES: usize = 2 * 1024 * 1024;

const MODULUS: &str = concat!(
    "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7",
    "b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280",
    "104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932",
    "575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b",
    "3ece0462db0a22b8e7"
);
fn cbc(text: &[u8], key: &[u8; 16]) -> String {
    STANDARD.encode(
        cbc::Encryptor::<aes::Aes128>::new(key.into(), b"0102030405060708".into())
            .encrypt_padded_vec_mut::<Pkcs7>(text),
    )
}
pub(crate) fn weapi(text: &str, key: &[u8; 16]) -> Result<Vec<(String, String)>, Error> {
    if text.len() > 64 * 1024 {
        return Err(Error::InputBound);
    }
    let first = cbc(text.as_bytes(), b"0CoJUm6Qyw8W8jud");
    let reversed: Vec<_> = key.iter().rev().copied().collect();
    let modulus = BigUint::parse_bytes(MODULUS.as_bytes(), 16).ok_or(Error::ProtocolUnavailable)?;
    let rsa = BigUint::from_bytes_be(&reversed).modpow(&BigUint::from(65537_u32), &modulus);
    Ok(vec![
        ("params".into(), cbc(first.as_bytes(), key)),
        ("encSecKey".into(), format!("{rsa:0256x}")),
    ])
}
pub(crate) fn random_key() -> Result<[u8; 16], Error> {
    const ALPHABET: &[u8; 62] = b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    let mut entropy = [0; 64];
    getrandom::fill(&mut entropy).map_err(|_| Error::ProtocolUnavailable)?;
    let mut selected = entropy
        .into_iter()
        .filter(|v| *v < 248)
        .map(|v| ALPHABET[usize::from(v % 62)]);
    let mut key = [0; 16];
    for byte in &mut key {
        *byte = selected.next().ok_or(Error::ProtocolUnavailable)?;
    }
    Ok(key)
}
pub(crate) fn eapi(path: &str, text: &str) -> Result<Vec<(String, String)>, Error> {
    if text.len() > 64 * 1024 || path.len() > 256 || !path.starts_with("/api/") {
        return Err(Error::InputBound);
    }
    let digest = format!(
        "{:x}",
        Md5::digest(format!("nobody{path}use{text}md5forencrypt"))
    );
    let mut input = format!("{path}-36cd479b6b5-{text}-36cd479b6b5-{digest}").into_bytes();
    let padding = u8::try_from(16 - input.len() % 16).map_err(|_| Error::InputBound)?;
    input.extend(std::iter::repeat_n(padding, usize::from(padding)));
    let cipher = aes::Aes128::new(b"e82ckenh8dichen8".into());
    for block in input.chunks_exact_mut(16) {
        cipher.encrypt_block(block.into());
    }
    let encoded: String = input
        .iter()
        .flat_map(|v| {
            [
                char::from(b"0123456789ABCDEF"[usize::from(v >> 4)]),
                char::from(b"0123456789ABCDEF"[usize::from(v & 15)]),
            ]
        })
        .collect();
    Ok(vec![("params".into(), encoded)])
}

fn maybe_gunzip(bytes: &[u8]) -> Result<Vec<u8>, Error> {
    if !bytes.starts_with(&[0x1f, 0x8b]) {
        return Ok(bytes.to_vec());
    }
    let mut decoded = Vec::new();
    GzDecoder::new(bytes)
        .take((MAX_DECODED_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut decoded)
        .map_err(|_| Error::ResponseShapeMismatch)?;
    if decoded.len() > MAX_DECODED_RESPONSE_BYTES {
        return Err(Error::ResponseBound);
    }
    Ok(decoded)
}

pub(crate) fn eapi_response(bytes: &[u8]) -> Result<Vec<u8>, Error> {
    let encrypted = maybe_gunzip(bytes)?;
    if encrypted.is_empty() || encrypted.len() % 16 != 0 {
        return Err(Error::ResponseShapeMismatch);
    }
    let cipher = aes::Aes128::new(b"e82ckenh8dichen8".into());
    let mut decoded = encrypted;
    for block in decoded.chunks_exact_mut(16) {
        cipher.decrypt_block(block.into());
    }
    let padding = usize::from(*decoded.last().ok_or(Error::ResponseShapeMismatch)?);
    if padding == 0
        || padding > 16
        || padding > decoded.len()
        || decoded[decoded.len() - padding..]
            .iter()
            .any(|byte| usize::from(*byte) != padding)
    {
        return Err(Error::ResponseShapeMismatch);
    }
    decoded.truncate(decoded.len() - padding);
    maybe_gunzip(&decoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independent_openssl_and_integer_known_answers() {
        let w = weapi(r#"{"fixture":1}"#, b"0123456789abcdef").unwrap();
        assert_eq!(w[0].1, "gOSc1a49n32qIiEsrSHXY6dr7AAfvlka/trTAwDp2Pc=");
        assert_eq!(
            w[1].1,
            "35701388baf89fed412e11269b9c76625d095ecaf17f03fa018abe19ea2d38b949debf242ee39a71ca1f6cda71b1b86a45aa909ee27f7e78e267d34e732f0de948206c3340a788d0003372183e2f753c1f78b66ac23d134ac1fc9b993156520ea826b8aa89a962d4491b4b8d7e08738e1da9b07aa39bf4a7ef0b1c210728cd52"
        );
        assert_eq!(
            eapi("/api/test", r#"{"fixture":1}"#).unwrap()[0].1,
            "4DC723619A991588865191FD2F319BAD7CFF4EA3DB99B2EC07F3BD93A12DE63EEDE25AE21B652D507DE5CC0557C5AB07DC42C0C6E4AC7616A2435C73423689A9F6569886F88AF9870BA85BEA1E6C24306AA3B102FBE7296AB0DB9EA5C46AD12B"
        );
    }
    #[test]
    fn input_bounds_are_checked_before_encryption() {
        assert!(weapi(&"x".repeat(65537), b"0123456789abcdef").is_err());
        assert!(eapi("/other", "{}").is_err());
    }

    #[test]
    fn mobile_eapi_response_uses_strict_pkcs7_decryption() {
        let mut encrypted = br#"{"code":200}"#.to_vec();
        let padding = 16 - encrypted.len() % 16;
        encrypted.extend(std::iter::repeat_n(u8::try_from(padding).unwrap(), padding));
        let cipher = aes::Aes128::new(b"e82ckenh8dichen8".into());
        for block in encrypted.chunks_exact_mut(16) {
            cipher.encrypt_block(block.into());
        }
        assert_eq!(eapi_response(&encrypted).unwrap(), br#"{"code":200}"#);

        let mut invalid = encrypted;
        *invalid.last_mut().unwrap() ^= 1;
        assert!(matches!(
            eapi_response(&invalid),
            Err(Error::ResponseShapeMismatch)
        ));
    }
}
